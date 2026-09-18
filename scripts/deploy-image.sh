#!/bin/bash
# =============================================================================
# deploy-image.sh – Deploy dashboard-app to AWS EKS
# Usage: bash scripts/deploy-image.sh  (run from repository root)
# =============================================================================
set -e
set -o pipefail

APP_NAME="dashboard-app"
NAMESPACE="dashboard-app"
K8S_DIR="kubernetes"

echo "=============================================="
echo "  dashboard-app – AWS EKS Deployment"
echo "=============================================="
echo ""

# ---------------------------------------------------------------------------
# Collect deployment parameters
# ---------------------------------------------------------------------------
read -rp "Enter AWS Region (e.g. us-east-1): " AWS_REGION
if [ -z "$AWS_REGION" ]; then
  echo "ERROR: AWS Region is required."
  exit 1
fi

read -rp "Enter EKS Cluster Name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
  echo "ERROR: EKS Cluster Name is required."
  exit 1
fi

read -rp "Enter full Docker image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
  echo "ERROR: Docker image URI is required."
  exit 1
fi

echo ""

# ---------------------------------------------------------------------------
# Configure kubectl for EKS
# ---------------------------------------------------------------------------
echo "Configuring kubectl for EKS cluster: $CLUSTER_NAME in $AWS_REGION ..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: Cannot connect to EKS cluster."; exit 1; }
echo ""

# ---------------------------------------------------------------------------
# Substitute {{IMAGE_URI}} placeholder in deployment manifest
# ---------------------------------------------------------------------------
echo "Updating Kubernetes manifests with image URI..."
# Work on a temporary copy to avoid modifying the source manifests permanently
cp "${K8S_DIR}/deployment.yaml" "${K8S_DIR}/deployment.yaml.bak"
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" "${K8S_DIR}/deployment.yaml"

# ---------------------------------------------------------------------------
# Apply manifests in dependency order
# ---------------------------------------------------------------------------
echo ""
echo "Applying Kubernetes manifests..."

echo "  [1/4] Applying namespace..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"

echo "  [2/4] Applying deployment..."
kubectl apply -f "${K8S_DIR}/deployment.yaml"

echo "  [3/4] Applying service..."
kubectl apply -f "${K8S_DIR}/service.yaml"

echo "  [4/4] Applying ingress..."
kubectl apply -f "${K8S_DIR}/ingress.yaml"

# ---------------------------------------------------------------------------
# Restore original deployment manifest (with placeholder)
# ---------------------------------------------------------------------------
mv "${K8S_DIR}/deployment.yaml.bak" "${K8S_DIR}/deployment.yaml"

# ---------------------------------------------------------------------------
# Wait for rollout to complete
# ---------------------------------------------------------------------------
echo ""
echo "Waiting for deployment rollout to complete..."
kubectl rollout status deployment/"${APP_NAME}" -n "${NAMESPACE}" --timeout=300s

# ---------------------------------------------------------------------------
# Verify deployed resources
# ---------------------------------------------------------------------------
echo ""
echo "Deployed resources in namespace '${NAMESPACE}':"
kubectl get pods,svc,ingress -n "${NAMESPACE}"

# ---------------------------------------------------------------------------
# Display application URL
# ---------------------------------------------------------------------------
echo ""
echo "Fetching application ingress URL..."
INGRESS_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "${NAMESPACE}" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$INGRESS_HOST" ]; then
  echo "Application is accessible at: http://${INGRESS_HOST}"
else
  echo "Ingress hostname not yet assigned. Run the following to check:"
  echo "  kubectl get ingress -n ${NAMESPACE}"
fi

echo ""
echo "=============================================="
echo "  Deployment Complete!"
echo "  App     : ${APP_NAME}"
echo "  Image   : ${IMAGE_URI}"
echo "  Cluster : ${CLUSTER_NAME}"
echo "  Region  : ${AWS_REGION}"
echo "=============================================="
echo ""
echo "Rollback command (if needed):"
echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
