#!/bin/bash
# =============================================================================
# deploy-image.sh — Deploy dashboard-app to AWS ECS Fargate
# Usage: ./scripts/deploy-image.sh  (run from repository root)
# =============================================================================
set -e
set -o pipefail

PROJECT_NAME="dashboard-app"
SERVICE_NAME="${PROJECT_NAME}-service"
TASK_FAMILY="${PROJECT_NAME}-task"
LOG_GROUP="/ecs/${PROJECT_NAME}"
TASK_DEF_FILE="ecs/task-definition.json"
SERVICE_DEF_FILE="ecs/service-definition.json"

echo "=============================================="
echo "  dashboard-app — ECS Fargate Deployment"
echo "=============================================="
echo ""

# ------------------------------------------------------------------------------
# Collect deployment parameters
# ------------------------------------------------------------------------------
read -rp "Enter AWS Region [us-east-1]: " AWS_REGION
AWS_REGION="${AWS_REGION:-us-east-1}"

read -rp "Enter ECS Cluster name [dashboard-app-cluster]: " CLUSTER_NAME
CLUSTER_NAME="${CLUSTER_NAME:-dashboard-app-cluster}"

read -rp "Enter ECR Image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
  echo "ERROR: Image URI is required."
  exit 1
fi

read -rp "Enter VPC ID (e.g. vpc-xxxxxxxx): " VPC_ID
if [ -z "$VPC_ID" ]; then
  echo "ERROR: VPC ID is required."
  exit 1
fi

read -rp "Enter Subnet IDs (comma-separated, e.g. subnet-aaa,subnet-bbb): " SUBNETS_INPUT
if [ -z "$SUBNETS_INPUT" ]; then
  echo "ERROR: At least one subnet ID is required."
  exit 1
fi

read -rp "Enter Security Group ID (e.g. sg-xxxxxxxx): " SECURITY_GROUP
if [ -z "$SECURITY_GROUP" ]; then
  echo "ERROR: Security Group ID is required."
  exit 1
fi

# Parse subnets into JSON array
SUBNET_1=$(echo "$SUBNETS_INPUT" | cut -d',' -f1 | tr -d ' ')
SUBNET_2=$(echo "$SUBNETS_INPUT" | cut -d',' -f2 | tr -d ' ')
if [ -z "$SUBNET_2" ]; then
  SUBNET_2="$SUBNET_1"
fi

# ------------------------------------------------------------------------------
# Retrieve AWS Account ID
# ------------------------------------------------------------------------------
echo ""
echo "Retrieving AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

# ------------------------------------------------------------------------------
# Ensure CloudWatch log group exists
# ------------------------------------------------------------------------------
echo ""
echo "Ensuring CloudWatch log group exists: $LOG_GROUP ..."
aws logs create-log-group --log-group-name "$LOG_GROUP" --region "$AWS_REGION" 2>/dev/null || true
echo "Log group ready: $LOG_GROUP"

# ------------------------------------------------------------------------------
# Ensure ECS cluster exists
# ------------------------------------------------------------------------------
echo ""
echo "Checking ECS cluster: $CLUSTER_NAME ..."
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query "clusters[0].status" --output text 2>/dev/null || echo "MISSING")

if [ "$CLUSTER_STATUS" != "ACTIVE" ]; then
  echo "Creating ECS cluster: $CLUSTER_NAME ..."
  aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
  echo "ECS cluster created: $CLUSTER_NAME"
else
  echo "ECS cluster already exists: $CLUSTER_NAME"
fi

# ------------------------------------------------------------------------------
# Load balancer (optional)
# ------------------------------------------------------------------------------
echo ""
read -rp "Do you need an Application Load Balancer for this service? (y/n) [n]: " NEED_LB
NEED_LB="${NEED_LB:-n}"

TARGET_GROUP_ARN=""
LB_DNS=""

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
  echo ""
  echo "Creating Application Load Balancer..."

  # Build subnet list for ALB (needs at least 2 subnets)
  SUBNET_LIST=$(echo "$SUBNETS_INPUT" | tr ',' ' ')

  LB_NAME="${PROJECT_NAME}-alb"
  TG_NAME="${PROJECT_NAME}-tg"

  # Create ALB
  LB_ARN=$(aws elbv2 create-load-balancer \
    --name "$LB_NAME" \
    --subnets $SUBNET_LIST \
    --security-groups "$SECURITY_GROUP" \
    --scheme internet-facing \
    --type application \
    --region "$AWS_REGION" \
    --query "LoadBalancers[0].LoadBalancerArn" \
    --output text)
  echo "ALB created: $LB_ARN"

  LB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "$LB_ARN" \
    --region "$AWS_REGION" \
    --query "LoadBalancers[0].DNSName" \
    --output text)

  # Create Target Group (target-type ip is required for Fargate awsvpc mode)
  TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
    --name "$TG_NAME" \
    --protocol HTTP \
    --port 8080 \
    --vpc-id "$VPC_ID" \
    --target-type ip \
    --health-check-path "/api/health" \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --region "$AWS_REGION" \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text)
  echo "Target Group created: $TARGET_GROUP_ARN"

  # Create listener
  aws elbv2 create-listener \
    --load-balancer-arn "$LB_ARN" \
    --protocol HTTP \
    --port 80 \
    --default-actions "Type=forward,TargetGroupArn=$TARGET_GROUP_ARN" \
    --region "$AWS_REGION" >/dev/null
  echo "ALB listener created (port 80 -> $TG_NAME)"
fi

# ------------------------------------------------------------------------------
# Prepare working copies of task/service definition files
# ------------------------------------------------------------------------------
WORK_DIR=$(mktemp -d)
cp "$TASK_DEF_FILE" "$WORK_DIR/task-definition.json"
cp "$SERVICE_DEF_FILE" "$WORK_DIR/service-definition.json"

# Replace placeholders in task definition
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g"     "$WORK_DIR/task-definition.json"
sed -i "s|{{AWS_REGION}}|${AWS_REGION}|g"   "$WORK_DIR/task-definition.json"
sed -i "s|{{ACCOUNT_ID}}|${ACCOUNT_ID}|g"   "$WORK_DIR/task-definition.json"

# Replace placeholders in service definition
sed -i "s|{{CLUSTER_NAME}}|${CLUSTER_NAME}|g"       "$WORK_DIR/service-definition.json"
sed -i "s|{{SUBNET_1}}|${SUBNET_1}|g"               "$WORK_DIR/service-definition.json"
sed -i "s|{{SUBNET_2}}|${SUBNET_2}|g"               "$WORK_DIR/service-definition.json"
sed -i "s|{{SECURITY_GROUP}}|${SECURITY_GROUP}|g"   "$WORK_DIR/service-definition.json"

# Handle load balancer section in service definition
if [[ "$NEED_LB" =~ ^[Yy]$ ]] && [ -n "$TARGET_GROUP_ARN" ]; then
  # Inject loadBalancers block before closing brace
  python3 - <<PYEOF
import json, sys

with open("$WORK_DIR/service-definition.json") as f:
    svc = json.load(f)

svc["loadBalancers"] = [
    {
        "targetGroupArn": "$TARGET_GROUP_ARN",
        "containerName": "dashboard-app",
        "containerPort": 8080
    }
]
svc["healthCheckGracePeriodSeconds"] = 300

with open("$WORK_DIR/service-definition.json", "w") as f:
    json.dump(svc, f, indent=2)
print("loadBalancers section injected.")
PYEOF
fi

# ------------------------------------------------------------------------------
# Register task definition
# ------------------------------------------------------------------------------
echo ""
echo "Registering ECS task definition: $TASK_FAMILY ..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json "file://$WORK_DIR/task-definition.json" \
  --region "$AWS_REGION" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)
echo "Task definition registered: $TASK_DEF_ARN"

# Update service definition to use the full ARN
sed -i "s|\"taskDefinition\": \"${TASK_FAMILY}\"|\"taskDefinition\": \"${TASK_DEF_ARN}\"|g" \
  "$WORK_DIR/service-definition.json"

# ------------------------------------------------------------------------------
# Create or update ECS service
# ------------------------------------------------------------------------------
echo ""
echo "Checking if ECS service exists: $SERVICE_NAME ..."
EXISTING_SERVICE=$(aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --region "$AWS_REGION" \
  --query "services[?status!='INACTIVE'].serviceName" \
  --output text 2>/dev/null || echo "")

if [ -z "$EXISTING_SERVICE" ] || [ "$EXISTING_SERVICE" = "None" ]; then
  echo "Creating ECS service: $SERVICE_NAME ..."
  aws ecs create-service \
    --cli-input-json "file://$WORK_DIR/service-definition.json" \
    --region "$AWS_REGION"
  echo "ECS service created: $SERVICE_NAME"
else
  echo "Updating existing ECS service: $SERVICE_NAME ..."
  aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --task-definition "$TASK_DEF_ARN" \
    --region "$AWS_REGION" >/dev/null
  echo "ECS service updated: $SERVICE_NAME"
fi

# ------------------------------------------------------------------------------
# Wait for service stability
# ------------------------------------------------------------------------------
echo ""
echo "Waiting for service to become stable (this may take a few minutes)..."
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --region "$AWS_REGION"
echo "Service is stable."

# ------------------------------------------------------------------------------
# Verify deployment
# ------------------------------------------------------------------------------
echo ""
echo "Verifying deployment..."
aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --region "$AWS_REGION" \
  --query "services[0].{ServiceName:serviceName,Status:status,DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount}"

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Deployment Complete!"
echo "  Cluster      : $CLUSTER_NAME"
echo "  Service      : $SERVICE_NAME"
echo "  Task Def ARN : $TASK_DEF_ARN"
echo "  Image        : $IMAGE_URI"
echo "  Log Group    : $LOG_GROUP"
if [ -n "$LB_DNS" ]; then
  echo "  ALB DNS      : http://$LB_DNS"
fi
echo "=============================================="
echo ""
echo "Troubleshooting tips:"
echo "  - View logs  : aws logs tail $LOG_GROUP --follow --region $AWS_REGION"
echo "  - List tasks : aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME --region $AWS_REGION"
echo "  - Stop tasks : aws ecs stop-task --cluster $CLUSTER_NAME --task <TASK_ARN> --region $AWS_REGION"

# Cleanup temp files
rm -rf "$WORK_DIR"
