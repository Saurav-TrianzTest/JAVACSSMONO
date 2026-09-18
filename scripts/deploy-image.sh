#!/usr/bin/env bash
# =============================================================================
# deploy-image.sh — Deploy dashboard-app to AWS ECS Fargate
# Application: dashboard-app (Spring Boot 3.2.5 / Java 17)
# =============================================================================
set -e
set -o pipefail

# -----------------------------------------------------------------------------
# Colour helpers
# -----------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
PROJECT_NAME="dashboard-app"
TASK_FAMILY="${PROJECT_NAME}-task"
SERVICE_NAME="${PROJECT_NAME}-service"
LOG_GROUP="/ecs/${PROJECT_NAME}"
TASK_DEF_FILE="ecs/task-definition.json"
SERVICE_DEF_FILE="ecs/service-definition.json"

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  dashboard-app — AWS ECS Fargate Deployment"
echo "  Spring Boot 3.2.5 / Java 17"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------------
# Prerequisite checks
# -----------------------------------------------------------------------------
info "Checking prerequisites..."
command -v aws  >/dev/null 2>&1 || { error "aws CLI not found. Install from https://aws.amazon.com/cli/"; exit 1; }
command -v jq   >/dev/null 2>&1 || { warn "jq not found — JSON parsing will use grep fallback."; }
success "Prerequisites OK."

# -----------------------------------------------------------------------------
# Gather deployment parameters
# -----------------------------------------------------------------------------
echo ""
info "=== Deployment Configuration ==="
read -rp "AWS Region (e.g. us-east-1)                          : " AWS_REGION
read -rp "ECS Cluster name [default: ${PROJECT_NAME}-cluster]  : " CLUSTER_INPUT
CLUSTER_NAME="${CLUSTER_INPUT:-${PROJECT_NAME}-cluster}"
read -rp "ECR Image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest): " IMAGE_URI
read -rp "VPC ID (e.g. vpc-xxxxxxxx)                           : " VPC_ID
read -rp "Subnet IDs (comma-separated, e.g. subnet-aaa,subnet-bbb): " SUBNETS_RAW
read -rp "Security Group ID (e.g. sg-xxxxxxxx)                 : " SECURITY_GROUP

# Parse subnets into array
IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNETS_RAW"
SUBNET_1="${SUBNET_ARRAY[0]}"
SUBNET_2="${SUBNET_ARRAY[1]:-${SUBNET_ARRAY[0]}}"

echo ""
info "Region        : $AWS_REGION"
info "Cluster       : $CLUSTER_NAME"
info "Image URI     : $IMAGE_URI"
info "VPC           : $VPC_ID"
info "Subnet 1      : $SUBNET_1"
info "Subnet 2      : $SUBNET_2"
info "Security Group: $SECURITY_GROUP"

# -----------------------------------------------------------------------------
# Retrieve AWS Account ID
# -----------------------------------------------------------------------------
echo ""
info "Retrieving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
success "Account ID    : $ACCOUNT_ID"

# -----------------------------------------------------------------------------
# Ensure CloudWatch log group exists
# -----------------------------------------------------------------------------
echo ""
info "Ensuring CloudWatch log group '${LOG_GROUP}' exists..."
aws logs create-log-group --log-group-name "$LOG_GROUP" --region "$AWS_REGION" 2>/dev/null \
  || info "Log group already exists."
success "CloudWatch log group ready: $LOG_GROUP"

# -----------------------------------------------------------------------------
# Ensure ECS cluster exists
# -----------------------------------------------------------------------------
echo ""
info "Checking ECS cluster '${CLUSTER_NAME}'..."
CLUSTER_STATUS=$(aws ecs describe-clusters \
  --clusters "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "clusters[0].status" \
  --output text 2>/dev/null || echo "NONE")

if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
  info "Cluster not found or inactive — creating '${CLUSTER_NAME}'..."
  aws ecs create-cluster \
    --cluster-name "$CLUSTER_NAME" \
    --region "$AWS_REGION" \
    --capacity-providers FARGATE FARGATE_SPOT \
    --tags key=Application,value=dashboard-app
  success "ECS cluster '${CLUSTER_NAME}' created."
else
  success "ECS cluster '${CLUSTER_NAME}' is ACTIVE."
fi

# -----------------------------------------------------------------------------
# Load Balancer (optional)
# -----------------------------------------------------------------------------
echo ""
read -rp "Do you need an Application Load Balancer for this service? (y/n) [default: n]: " NEED_LB
NEED_LB="${NEED_LB:-n}"
TARGET_GROUP_ARN=""

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
  info "Creating Application Load Balancer..."

  # Create ALB
  ALB_NAME="${PROJECT_NAME}-alb"
  info "Creating ALB '${ALB_NAME}'..."
  ALB_ARN=$(aws elbv2 create-load-balancer \
    --name "$ALB_NAME" \
    --subnets "$SUBNET_1" "$SUBNET_2" \
    --security-groups "$SECURITY_GROUP" \
    --scheme internet-facing \
    --type application \
    --ip-address-type ipv4 \
    --region "$AWS_REGION" \
    --query "LoadBalancers[0].LoadBalancerArn" \
    --output text)
  success "ALB created: $ALB_ARN"

  ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$ALB_ARN" \
    --region "$AWS_REGION" \
    --query "LoadBalancers[0].DNSName" \
    --output text)

  # Create Target Group (target-type=ip required for Fargate awsvpc mode)
  TG_NAME="${PROJECT_NAME}-tg"
  info "Creating Target Group '${TG_NAME}' (target-type: ip)..."
  TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
    --name "$TG_NAME" \
    --protocol HTTP \
    --port 8080 \
    --vpc-id "$VPC_ID" \
    --target-type ip \
    --health-check-protocol HTTP \
    --health-check-path "/api/health" \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 10 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --region "$AWS_REGION" \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text)
  success "Target Group created: $TARGET_GROUP_ARN"

  # Create ALB Listener
  info "Creating ALB Listener on port 80..."
  aws elbv2 create-listener \
    --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
    --region "$AWS_REGION" \
    > /dev/null
  success "ALB Listener created."
fi

# -----------------------------------------------------------------------------
# Prepare task definition — replace placeholders
# -----------------------------------------------------------------------------
echo ""
info "Preparing task definition..."
TASK_DEF_TMP=$(mktemp /tmp/task-definition-XXXXXX.json)
cp "$TASK_DEF_FILE" "$TASK_DEF_TMP"

sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g"       "$TASK_DEF_TMP"
sed -i "s|{{AWS_REGION}}|${AWS_REGION}|g"     "$TASK_DEF_TMP"
sed -i "s|{{ACCOUNT_ID}}|${ACCOUNT_ID}|g"     "$TASK_DEF_TMP"

success "Task definition prepared: $TASK_DEF_TMP"

# -----------------------------------------------------------------------------
# Register task definition
# -----------------------------------------------------------------------------
info "Registering ECS task definition '${TASK_FAMILY}'..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json "file://${TASK_DEF_TMP}" \
  --region "$AWS_REGION" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)
success "Task definition registered: $TASK_DEF_ARN"

# -----------------------------------------------------------------------------
# Prepare service definition — replace placeholders
# -----------------------------------------------------------------------------
info "Preparing service definition..."
SERVICE_DEF_TMP=$(mktemp /tmp/service-definition-XXXXXX.json)
cp "$SERVICE_DEF_FILE" "$SERVICE_DEF_TMP"

sed -i "s|{{CLUSTER_NAME}}|${CLUSTER_NAME}|g"     "$SERVICE_DEF_TMP"
sed -i "s|{{SUBNET_1}}|${SUBNET_1}|g"             "$SERVICE_DEF_TMP"
sed -i "s|{{SUBNET_2}}|${SUBNET_2}|g"             "$SERVICE_DEF_TMP"
sed -i "s|{{SECURITY_GROUP}}|${SECURITY_GROUP}|g" "$SERVICE_DEF_TMP"

# Inject load balancer configuration if ALB was created
if [ -n "$TARGET_GROUP_ARN" ]; then
  info "Injecting load balancer configuration into service definition..."
  # Use Python to inject loadBalancers JSON (avoids complex sed escaping)
  python3 - <<PYEOF
import json, sys
with open('${SERVICE_DEF_TMP}', 'r') as f:
    svc = json.load(f)
svc['loadBalancers'] = [{
    'targetGroupArn': '${TARGET_GROUP_ARN}',
    'containerName': 'dashboard-app',
    'containerPort': 8080
}]
svc['healthCheckGracePeriodSeconds'] = 300
with open('${SERVICE_DEF_TMP}', 'w') as f:
    json.dump(svc, f, indent=2)
print('[INFO]  Load balancer configuration injected.')
PYEOF
fi

success "Service definition prepared: $SERVICE_DEF_TMP"

# -----------------------------------------------------------------------------
# Create or update ECS service
# -----------------------------------------------------------------------------
echo ""
info "Checking if ECS service '${SERVICE_NAME}' exists..."
EXISTING_SERVICE=$(aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --region "$AWS_REGION" \
  --query "services[?status!='INACTIVE'].serviceName" \
  --output text 2>/dev/null || echo "")

if [ -z "$EXISTING_SERVICE" ] || [ "$EXISTING_SERVICE" = "None" ]; then
  info "Service does not exist — creating '${SERVICE_NAME}'..."
  aws ecs create-service \
    --cli-input-json "file://${SERVICE_DEF_TMP}" \
    --region "$AWS_REGION" \
    > /dev/null
  success "ECS service '${SERVICE_NAME}' created."
else
  info "Service exists — updating '${SERVICE_NAME}' with new task definition..."
  aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --task-definition "$TASK_DEF_ARN" \
    --region "$AWS_REGION" \
    > /dev/null
  success "ECS service '${SERVICE_NAME}' updated."
fi

# -----------------------------------------------------------------------------
# Wait for service stability
# -----------------------------------------------------------------------------
echo ""
info "Waiting for service to reach stable state (this may take a few minutes)..."
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --region "$AWS_REGION"
success "Service is stable."

# -----------------------------------------------------------------------------
# Verify deployment
# -----------------------------------------------------------------------------
echo ""
info "Verifying deployment..."
aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --region "$AWS_REGION" \
  --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}" \
  --output table

# -----------------------------------------------------------------------------
# Cleanup temp files
# -----------------------------------------------------------------------------
rm -f "$TASK_DEF_TMP" "$SERVICE_DEF_TMP"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "============================================================"
success "Deployment complete!"
echo ""
echo "  Cluster       : $CLUSTER_NAME"
echo "  Service       : $SERVICE_NAME"
echo "  Task Def ARN  : $TASK_DEF_ARN"
echo "  CloudWatch    : $LOG_GROUP"
if [ -n "$ALB_DNS" ]; then
  echo "  Load Balancer : http://${ALB_DNS}"
  echo "  Health Check  : http://${ALB_DNS}/api/health"
fi
echo "============================================================"
echo ""
info "Troubleshooting:"
info "  View logs  : aws logs tail ${LOG_GROUP} --follow --region ${AWS_REGION}"
info "  List tasks : aws ecs list-tasks --cluster ${CLUSTER_NAME} --service-name ${SERVICE_NAME} --region ${AWS_REGION}"
info "  Stop svc   : aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --desired-count 0 --region ${AWS_REGION}"
echo ""
