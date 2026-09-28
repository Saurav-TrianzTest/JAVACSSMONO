#!/bin/bash
set -e
set -o pipefail

# =============================================================================
# deploy-image.sh — Deploy dashboard-app to Azure AKS
# Usage: ./scripts/deploy-image.sh
# Run from repository root directory
# Prerequisites: azure-cli, kubectl
# =============================================================================

APP_NAME="dashboard-app"
NAMESPACE="dashboard-app"

echo "=============================================="
echo "  Deploy $APP_NAME to Azure AKS"
echo "=============================================="
echo ""

# Prompt for Azure resource group
read -rp "Enter Azure Resource Group name: " RESOURCE_GROUP
if [ -z "$RESOURCE_GROUP" ]; then
  echo "ERROR: Resource group cannot be empty." >&2
  exit 1
fi

# Prompt for AKS cluster name
read -rp "Enter AKS Cluster name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
  echo "ERROR: AKS cluster name cannot be empty." >&2
  exit 1
fi

# Prompt for Docker image URI
read -rp "Enter full Docker image URI (e.g. myregistry.azurecr.io/dashboard-app:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
  echo "ERROR: Image URI cannot be empty." >&2
  exit 1
fi

echo ""
echo "--- Configuration ---"
echo "  Resource Group : $RESOURCE_GROUP"
echo "  AKS Cluster    : $CLUSTER_NAME"
echo "  Image URI      : $IMAGE_URI"
echo "  Namespace      : $NAMESPACE"
echo ""

# Configure kubectl credentials for AKS
echo "Configuring kubectl for AKS cluster: $CLUSTER_NAME ..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to get AKS credentials." >&2
  exit 1
fi

# Verify cluster connectivity
echo "Verifying cluster connectivity ..."
kubectl cluster-info || { echo "ERROR: Cannot connect to Kubernetes cluster." >&2; exit 1; }
echo ""

# Update deployment manifest with actual image URI (pipe delimiter for sed)
echo "Updating Kubernetes manifests with image URI ..."
sed -i 's|{{IMAGE_URI}}|'"$IMAGE_URI"'|g' kubernetes/deployment.yaml

# Apply manifests in order
echo "Applying Kubernetes manifests ..."

echo "  [1/4] Applying namespace ..."
kubectl apply -f kubernetes/namespace.yaml

echo "  [2/4] Applying deployment ..."
kubectl apply -f kubernetes/deployment.yaml

echo "  [3/4] Applying service ..."
kubectl apply -f kubernetes/service.yaml

echo "  [4/4] Applying ingress ..."
kubectl apply -f kubernetes/ingress.yaml

echo ""
echo "Waiting for deployment rollout ..."
kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s
if [ $? -ne 0 ]; then
  echo "ERROR: Deployment rollout failed. Running rollback ..." >&2
  kubectl rollout undo deployment/"$APP_NAME" -n "$NAMESPACE"
  echo "Rollback initiated. Check pod status with: kubectl get pods -n $NAMESPACE"
  exit 1
fi

echo ""
echo "Verifying deployed resources ..."
kubectl get pods,svc,ingress -n "$NAMESPACE"

echo ""
# Retrieve ingress host for application URL
INGRESS_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "dashboard-app.example.com")
echo "=============================================="
echo "  Deployment successful!"
echo "  Application URL: http://$INGRESS_HOST"
echo "  Health Check   : http://$INGRESS_HOST/api/health"
echo "=============================================="
echo ""
echo "Useful commands:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl logs -l app=$APP_NAME -n $NAMESPACE"
echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE  # rollback"
