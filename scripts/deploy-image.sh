#!/bin/bash
set -e
set -o pipefail

APP_NAME="dashboard-app"
NAMESPACE="dashboard-app"

read -r -p "AWS region (e.g. us-east-1): " AWS_REGION
[ -n "$AWS_REGION" ] || { echo "AWS region is required"; exit 1; }
read -r -p "EKS cluster name: " CLUSTER_NAME
[ -n "$CLUSTER_NAME" ] || { echo "Cluster name is required"; exit 1; }
read -r -p "Docker image URI (registry/repo:tag): " IMAGE_URI
[ -n "$IMAGE_URI" ] || { echo "Image URI is required"; exit 1; }
read -r -p "Enter value for SPRING_PROFILES_ACTIVE (or press Enter for 'docker'): " SPRING_PROFILES_ACTIVE
SPRING_PROFILES_ACTIVE=${SPRING_PROFILES_ACTIVE:-docker}

# Work on a temp copy so the template manifests keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR"/

sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$WORK_DIR"/*.yaml
sed -i.bak "s|{{SPRING_PROFILES_ACTIVE}}|$SPRING_PROFILES_ACTIVE|g" "$WORK_DIR"/*.yaml
sed -i.bak "s|{{NAMESPACE}}|$NAMESPACE|g" "$WORK_DIR"/*.yaml
rm -f "$WORK_DIR"/*.bak

echo "Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "Cannot reach cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

ALB_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$ALB_HOST" ]; then
  echo "Application URL: http://$ALB_HOST/api/health"
else
  echo "Ingress address not yet assigned. Check later: kubectl get ingress -n $NAMESPACE"
fi
