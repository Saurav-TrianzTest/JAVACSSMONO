#!/usr/bin/env bash
# =============================================================================
# deploy-image.sh — Deploy dashboard-app to AWS ECS Fargate
# Platform: Linux / macOS
# Usage: ./scripts/deploy-image.sh
# Run from the repository root directory.
# =============================================================================
set -e
set -o pipefail

SERVICE_NAME="dashboard-app-service"
TASK_FAMILY="dashboard-app-task"
LOG_GROUP="/ecs/dashboard-app"
TASK_DEF_FILE="ecs/task-definition.json"
SERVICE_DEF_FILE="ecs/service-definition.json"

echo "=============================================="
echo "  dashboard-app — ECS Fargate Deployment"
echo "=============================================="
echo ""

# ── AWS Region ────────────────────────────────────────────────────────────────
read -rp "AWS Region [us-east-1]: " AWS_REGION
AWS_REGION="${AWS_REGION:-us-east-1}"

# ── ECS Cluster ───────────────────────────────────────────────────────────────
read -rp "ECS Cluster name [dashboard-app-cluster]: " CLUSTER_NAME
CLUSTER_NAME="${CLUSTER_NAME:-dashboard-app-cluster}"

# ── Network configuration ─────────────────────────────────────────────────────
echo ""
echo "── Network Configuration ──────────────────────────────────────────────"
read -rp "VPC ID (e.g. vpc-xxxxxxxx): " VPC_ID
read -rp "Subnet IDs (comma-separated, e.g. subnet-aaa,subnet-bbb): " SUBNETS_RAW
read -rp "Security Group ID (e.g. sg-xxxxxxxx): " SECURITY_GROUP

# Parse subnets into SUBNET_1 and SUBNET_2
SUBNET_1=$(echo "${SUBNETS_RAW}" | cut -d',' -f1 | tr -d ' ')
SUBNET_2=$(echo "${SUBNETS_RAW}" | cut -d',' -f2 | tr -d ' ')
if [ -z "${SUBNET_2}" ]; then
  SUBNET_2="${SUBNET_1}"
fi

# ── ECR Image URI ─────────────────────────────────────────────────────────────
echo ""
read -rp "ECR Image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest): " IMAGE_URI

# ── AWS Account ID ────────────────────────────────────────────────────────────
echo ""
echo "Fetching AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID    : ${ACCOUNT_ID}"

# ── Ensure CloudWatch log group exists ────────────────────────────────────────
echo ""
echo "Ensuring CloudWatch log group '${LOG_GROUP}' exists..."
aws logs create-log-group --log-group-name "${LOG_GROUP}" --region "${AWS_REGION}" 2>/dev/null || true
echo "Log group ready."

# ── Ensure ECS cluster exists ─────────────────────────────────────────────────
echo ""
echo "Checking ECS cluster '${CLUSTER_NAME}'..."
CLUSTER_STATUS=$(aws ecs describe-clusters --clusters "${CLUSTER_NAME}" --region "${AWS_REGION}" \
  --query "clusters[0].status" --output text 2>/dev/null || echo "MISSING")
if [ "${CLUSTER_STATUS}" != "ACTIVE" ]; then
  echo "Creating ECS cluster '${CLUSTER_NAME}'..."
  aws ecs create-cluster --cluster-name "${CLUSTER_NAME}" --region "${AWS_REGION}"
fi
echo "Cluster ready."

# ── Load balancer prompt ──────────────────────────────────────────────────────
echo ""
read -rp "Do you need an Application Load Balancer for this service? (y/n) [n]: " NEED_LB
NEED_LB="${NEED_LB:-n}"

TARGET_GROUP_ARN=""
ALB_DNS=""

if [[ "${NEED_LB}" =~ ^[Yy]$ ]]; then
  echo ""
  echo "── Creating Application Load Balancer ─────────────────────────────────"

  # Create ALB
  ALB_NAME="dashboard-app-alb"
  echo "Creating ALB '${ALB_NAME}'..."
  ALB_ARN=$(aws elbv2 create-load-balancer \
    --name "${ALB_NAME}" \
    --subnets ${SUBNET_1} ${SUBNET_2} \
    --security-groups "${SECURITY_GROUP}" \
    --scheme internet-facing \
    --type application \
    --region "${AWS_REGION}" \
    --query "LoadBalancers[0].LoadBalancerArn" \
    --output text)
  echo "ALB ARN       : ${ALB_ARN}"

  ALB_DNS=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns "${ALB_ARN}" \
    --region "${AWS_REGION}" \
    --query "LoadBalancers[0].DNSName" \
    --output text)

  # Create Target Group (target-type ip required for Fargate awsvpc mode)
  TG_NAME="dashboard-app-tg"
  echo "Creating Target Group '${TG_NAME}'..."
  TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
    --name "${TG_NAME}" \
    --protocol HTTP \
    --port 8080 \
    --vpc-id "${VPC_ID}" \
    --target-type ip \
    --health-check-path "/api/health" \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --region "${AWS_REGION}" \
    --query "TargetGroups[0].TargetGroupArn" \
    --output text)
  echo "Target Group  : ${TARGET_GROUP_ARN}"

  # Create ALB Listener
  echo "Creating ALB Listener on port 80..."
  aws elbv2 create-listener \
    --load-balancer-arn "${ALB_ARN}" \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn="${TARGET_GROUP_ARN}" \
    --region "${AWS_REGION}" >/dev/null
  echo "ALB Listener created."
fi

# ── Substitute placeholders in task definition ────────────────────────────────
echo ""
echo "Preparing task definition..."
TASK_DEF_TMP=$(mktemp /tmp/task-definition-XXXXXX.json)
cp "${TASK_DEF_FILE}" "${TASK_DEF_TMP}"

sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g"       "${TASK_DEF_TMP}"
sed -i "s|{{AWS_REGION}}|${AWS_REGION}|g"     "${TASK_DEF_TMP}"
sed -i "s|{{ACCOUNT_ID}}|${ACCOUNT_ID}|g"     "${TASK_DEF_TMP}"

# ── Register task definition ──────────────────────────────────────────────────
echo "Registering ECS task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json "file://${TASK_DEF_TMP}" \
  --region "${AWS_REGION}" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)
echo "Task Def ARN  : ${TASK_DEF_ARN}"
rm -f "${TASK_DEF_TMP}"

# ── Substitute placeholders in service definition ─────────────────────────────
echo ""
echo "Preparing service definition..."
SERVICE_DEF_TMP=$(mktemp /tmp/service-definition-XXXXXX.json)
cp "${SERVICE_DEF_FILE}" "${SERVICE_DEF_TMP}"

sed -i "s|{{CLUSTER_NAME}}|${CLUSTER_NAME}|g"     "${SERVICE_DEF_TMP}"
sed -i "s|{{SUBNET_1}}|${SUBNET_1}|g"             "${SERVICE_DEF_TMP}"
sed -i "s|{{SUBNET_2}}|${SUBNET_2}|g"             "${SERVICE_DEF_TMP}"
sed -i "s|{{SECURITY_GROUP}}|${SECURITY_GROUP}|g" "${SERVICE_DEF_TMP}"

# ── Inject load balancer config if requested ──────────────────────────────────
if [[ "${NEED_LB}" =~ ^[Yy]$ ]] && [ -n "${TARGET_GROUP_ARN}" ]; then
  # Insert loadBalancers and healthCheckGracePeriodSeconds into service JSON
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
PYEOF
fi

# ── Create or update ECS service ──────────────────────────────────────────────
echo ""
echo "Checking if ECS service '${SERVICE_NAME}' exists..."
EXISTING_SERVICE=$(aws ecs describe-services \
  --cluster "${CLUSTER_NAME}" \
  --services "${SERVICE_NAME}" \
  --region "${AWS_REGION}" \
  --query "services[?status=='ACTIVE'].serviceName" \
  --output text 2>/dev/null || echo "")

if [ -z "${EXISTING_SERVICE}" ] || [ "${EXISTING_SERVICE}" = "None" ]; then
  echo "Creating ECS service '${SERVICE_NAME}'..."
  aws ecs create-service \
    --cli-input-json "file://${SERVICE_DEF_TMP}" \
    --region "${AWS_REGION}"
  echo "Service created."
else
  echo "Updating existing ECS service '${SERVICE_NAME}'..."
  aws ecs update-service \
    --cluster "${CLUSTER_NAME}" \
    --service "${SERVICE_NAME}" \
    --task-definition "${TASK_DEF_ARN}" \
    --region "${AWS_REGION}" >/dev/null
  echo "Service updated."
fi

rm -f "${SERVICE_DEF_TMP}"

# ── Wait for service stability ────────────────────────────────────────────────
echo ""
echo "Waiting for service to reach stable state (this may take a few minutes)..."
aws ecs wait services-stable \
  --cluster "${CLUSTER_NAME}" \
  --services "${SERVICE_NAME}" \
  --region "${AWS_REGION}"
echo "Service is stable."

# ── Verify deployment ─────────────────────────────────────────────────────────
echo ""
echo "── Deployment Summary ─────────────────────────────────────────────────"
aws ecs describe-services \
  --cluster "${CLUSTER_NAME}" \
  --services "${SERVICE_NAME}" \
  --region "${AWS_REGION}" \
  --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}" \
  --output table

echo ""
echo "CloudWatch Logs : ${LOG_GROUP}"
echo "ECS Cluster     : ${CLUSTER_NAME}"
echo "ECS Service     : ${SERVICE_NAME}"
echo "Task Definition : ${TASK_DEF_ARN}"

if [ -n "${ALB_DNS}" ]; then
  echo ""
  echo "Load Balancer DNS : http://${ALB_DNS}"
  echo "Health Check URL  : http://${ALB_DNS}/api/health"
fi

echo ""
echo "=============================================="
echo "  Deployment complete!"
echo "=============================================="
echo ""
echo "Troubleshooting hints:"
echo "  - View task logs  : aws logs tail ${LOG_GROUP} --follow --region ${AWS_REGION}"
echo "  - List tasks      : aws ecs list-tasks --cluster ${CLUSTER_NAME} --region ${AWS_REGION}"
echo "  - Describe tasks  : aws ecs describe-tasks --cluster ${CLUSTER_NAME} --tasks <task-arn> --region ${AWS_REGION}"
echo "  - Service events  : aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION} --query 'services[0].events[:5]'"
