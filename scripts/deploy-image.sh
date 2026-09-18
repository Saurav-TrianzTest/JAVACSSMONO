#!/usr/bin/env bash
# =============================================================================
# deploy-image.sh — Deploy dashboard-app to Azure AKS
# Usage: bash scripts/deploy-image.sh
# =============================================================================
set -e
set -o pipefail

APP_NAME="dashboard-app"
NAMESPACE="dashboard-app"
MANIFEST_DIR="kubernetes"

echo "=============================================="
echo "  dashboard-app — Deploy to Azure AKS"
echo "=============================================="
echo ""

# ── Validate required tools ───────────────────────────────────────────────────
for tool in az kubectl sed; do
  if ! command -v "$tool" &>/dev/null; then
    echo "ERROR: '$tool' is not installed or not in PATH." >&2
    exit 1
  fi
done

# ── Prompt for Azure details ──────────────────────────────────────────────────
read -rp "Enter Azure Resource Group name: " RESOURCE_GROUP
if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "ERROR: Resource group cannot be empty." >&2
  exit 1
fi

read -rp "Enter AKS Cluster name: " CLUSTER_NAME
if [[ -z "$CLUSTER_NAME" ]]; then
  echo "ERROR: AKS cluster name cannot be empty." >&2
  exit 1
fi

# ── Prompt for Docker image URI ───────────────────────────────────────────────
read -rp "Enter full Docker image URI (e.g. myregistry.azurecr.io/dashboard-app:latest): " IMAGE_URI
if [[ -z "$IMAGE_URI" ]]; then
  echo "ERROR: Image URI cannot be empty." >&2
  exit 1
fi

echo ""
echo "Configuration:"
echo "  Resource Group : $RESOURCE_GROUP"
echo "  AKS Cluster    : $CLUSTER_NAME"
echo "  Image URI      : $IMAGE_URI"
echo "  Namespace      : $NAMESPACE"
echo ""

# ── Configure kubectl ─────────────────────────────────────────────────────────
echo "Configuring kubectl for AKS cluster ..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
echo "kubectl configured successfully."
echo ""

# ── Verify cluster connectivity ───────────────────────────────────────────────
echo "Verifying cluster connectivity ..."
kubectl cluster-info || { echo "ERROR: Cannot connect to AKS cluster." >&2; exit 1; }
echo ""

# ── Patch manifests with actual image URI ────────────────────────────────────
echo "Updating Kubernetes manifests ..."
# Use pipe delimiter to safely handle URIs containing forward slashes
sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" "${MANIFEST_DIR}/deployment.yaml"
echo "  deployment.yaml updated with image: $IMAGE_URI"
echo ""

# ── Apply manifests in order ──────────────────────────────────────────────────
echo "Applying Kubernetes manifests ..."

echo "  [1/4] Applying namespace ..."
kubectl apply -f "${MANIFEST_DIR}/namespace.yaml"

echo "  [2/4] Applying deployment ..."
kubectl apply -f "${MANIFEST_DIR}/deployment.yaml"

echo "  [3/4] Applying service ..."
kubectl apply -f "${MANIFEST_DIR}/service.yaml"

echo "  [4/4] Applying ingress ..."
kubectl apply -f "${MANIFEST_DIR}/ingress.yaml"

echo ""

# ── Wait for rollout ──────────────────────────────────────────────────────────
echo "Waiting for deployment rollout ..."
kubectl rollout status deployment/"${APP_NAME}" -n "${NAMESPACE}" --timeout=300s
echo "Deployment rollout complete."
echo ""

# ── Verify resources ──────────────────────────────────────────────────────────
echo "Verifying deployed resources ..."
kubectl get pods,svc,ingress -n "${NAMESPACE}"
echo ""

# ── Display application URL ───────────────────────────────────────────────────
INGRESS_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "${NAMESPACE}" \
  -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "dashboard-app.example.com")

echo "=============================================="
echo "  Deployment complete!"
echo "  Application URL: http://${INGRESS_HOST}"
echo "  Health check   : http://${INGRESS_HOST}/api/health"
echo ""
echo "  Rollback command (if needed):"
echo "    kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
echo "=============================================="
