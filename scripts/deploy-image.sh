#!/bin/bash
# =============================================================================
# deploy-image.sh — Deploy dashboard-app to AWS EKS
# Usage: ./scripts/deploy-image.sh
# =============================================================================
set -e
set -o pipefail

APP_NAME="dashboard-app"
NAMESPACE="dashboard-app"
K8S_DIR="kubernetes"

echo "=============================================="
echo "  dashboard-app — AWS EKS Deployment"
echo "=============================================="
echo ""

# ── Prompt for AWS / EKS configuration ───────────────────────────────────────
read -rp "Enter AWS Region [us-east-1]: " AWS_REGION
AWS_REGION="${AWS_REGION:-us-east-1}"

read -rp "Enter EKS Cluster Name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
  echo "ERROR: EKS Cluster Name is required." >&2
  exit 1
fi

read -rp "Enter Docker Image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
  echo "ERROR: Docker Image URI is required." >&2
  exit 1
fi

echo ""
echo "Configuration:"
echo "  AWS Region   : ${AWS_REGION}"
echo "  EKS Cluster  : ${CLUSTER_NAME}"
echo "  Image URI    : ${IMAGE_URI}"
echo "  Namespace    : ${NAMESPACE}"
echo ""

# ── Configure kubectl for EKS ─────────────────────────────────────────────────
echo "Configuring kubectl for EKS cluster '${CLUSTER_NAME}'..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"
echo "kubectl configured successfully."
echo ""

# ── Verify cluster connectivity ───────────────────────────────────────────────
echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: Cannot connect to EKS cluster." >&2; exit 1; }
echo ""

# ── Substitute placeholders in manifests ─────────────────────────────────────
echo "Updating Kubernetes manifests with image URI..."
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" "${K8S_DIR}/deployment.yaml"
echo "Manifests updated."
echo ""

# ── Apply Kubernetes manifests ────────────────────────────────────────────────
echo "Applying namespace..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"

echo "Applying deployment..."
kubectl apply -f "${K8S_DIR}/deployment.yaml"

echo "Applying service..."
kubectl apply -f "${K8S_DIR}/service.yaml"

echo "Applying ingress..."
kubectl apply -f "${K8S_DIR}/ingress.yaml"
echo ""

# ── Wait for rollout ──────────────────────────────────────────────────────────
echo "Waiting for deployment rollout..."
kubectl rollout status deployment/"${APP_NAME}" -n "${NAMESPACE}" --timeout=300s || {
  echo ""
  echo "ERROR: Deployment rollout timed out or failed." >&2
  echo "Run the following to investigate:"
  echo "  kubectl describe deployment/${APP_NAME} -n ${NAMESPACE}"
  echo "  kubectl get pods -n ${NAMESPACE}"
  echo "  kubectl logs -l app=${APP_NAME} -n ${NAMESPACE} --tail=50"
  echo ""
  echo "To rollback:"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
  exit 1
}
echo ""

# ── Verify resources ──────────────────────────────────────────────────────────
echo "Verifying deployed resources..."
kubectl get pods,svc,ingress -n "${NAMESPACE}"
echo ""

# ── Display application URL ───────────────────────────────────────────────────
echo "Fetching application ingress URL..."
INGRESS_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "${NAMESPACE}" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$INGRESS_HOST" ]; then
  echo ""
  echo "=============================================="
  echo "  Deployment successful!"
  echo "  Application URL: http://${INGRESS_HOST}"
  echo "  Health Check   : http://${INGRESS_HOST}/health"
  echo "  API Endpoint   : http://${INGRESS_HOST}/api/health"
  echo "=============================================="
else
  echo ""
  echo "=============================================="
  echo "  Deployment successful!"
  echo "  Ingress hostname not yet assigned."
  echo "  Run: kubectl get ingress -n ${NAMESPACE}"
  echo "  to retrieve the ALB hostname once provisioned."
  echo "=============================================="
fi
