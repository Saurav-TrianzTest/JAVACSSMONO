#!/bin/bash
# =============================================================================
# build-push.sh — Build and push the dashboard-app Docker image
# Supports: AWS ECR and Docker Hub
# Usage: ./scripts/build-push.sh  (run from repository root)
# =============================================================================
set -e

PROJECT_NAME="dashboard-app"
DOCKERFILE_PATH="Dockerfile"

echo "=============================================="
echo "  dashboard-app — Docker Build & Push"
echo "=============================================="
echo ""

# ------------------------------------------------------------------------------
# Sanitize project name: lowercase, replace non-alphanumeric with hyphens,
# strip leading/trailing hyphens.
# ------------------------------------------------------------------------------
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

# ------------------------------------------------------------------------------
# Prompt for image tag
# ------------------------------------------------------------------------------
read -rp "Enter image tag [latest]: " IMAGE_TAG_INPUT
IMAGE_TAG=$(echo "${IMAGE_TAG_INPUT:-latest}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
if [ -z "$IMAGE_TAG" ]; then
  IMAGE_TAG="latest"
fi
echo "Image tag: $IMAGE_TAG"
echo ""

# ------------------------------------------------------------------------------
# Registry selection
# ------------------------------------------------------------------------------
echo "Select container registry:"
echo "  1. AWS ECR"
echo "  2. Docker Hub"
read -rp "Enter choice [1]: " REGISTRY_CHOICE
REGISTRY_CHOICE="${REGISTRY_CHOICE:-1}"

if [ "$REGISTRY_CHOICE" = "1" ]; then
  # --------------------------------------------------------------------------
  # AWS ECR
  # --------------------------------------------------------------------------
  echo ""
  echo "--- AWS ECR Configuration ---"
  read -rp "Enter AWS Region [us-east-1]: " AWS_REGION
  AWS_REGION="${AWS_REGION:-us-east-1}"

  # Derive account ID automatically
  echo "Retrieving AWS Account ID..."
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  echo "AWS Account ID: $ACCOUNT_ID"

  ECR_REPO="${IMAGE_NAME}"
  REGISTRY_URL="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

  echo ""
  echo "Logging in to Amazon ECR..."
  aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$REGISTRY_URL"

  # Auto-create ECR repository if it does not exist
  echo "Checking ECR repository: $ECR_REPO ..."
  aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
  echo "ECR repository ready: $ECR_REPO"

elif [ "$REGISTRY_CHOICE" = "2" ]; then
  # --------------------------------------------------------------------------
  # Docker Hub
  # --------------------------------------------------------------------------
  echo ""
  echo "--- Docker Hub Configuration ---"
  read -rp "Enter Docker Hub username: " DOCKER_USERNAME
  read -rsp "Enter Docker Hub password/token: " DOCKER_PASSWORD
  echo ""
  read -rp "Enter Docker Hub repository name [$IMAGE_NAME]: " DOCKER_REPO
  DOCKER_REPO="${DOCKER_REPO:-$IMAGE_NAME}"

  FULL_IMAGE_NAME="${DOCKER_USERNAME}/${DOCKER_REPO}:${IMAGE_TAG}"

  echo "Logging in to Docker Hub..."
  echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin

else
  echo "ERROR: Invalid registry choice '$REGISTRY_CHOICE'. Exiting."
  exit 1
fi

echo ""
echo "Full image name: $FULL_IMAGE_NAME"
echo ""

# ------------------------------------------------------------------------------
# Build Docker image
# Build context is always the repository root (.)
# ------------------------------------------------------------------------------
echo "Building Docker image..."
docker build -f "$DOCKERFILE_PATH" -t "$FULL_IMAGE_NAME" .
echo "Docker image built successfully."

# Also tag as latest for convenience
if [ "$IMAGE_TAG" != "latest" ]; then
  if [ "$REGISTRY_CHOICE" = "1" ]; then
    docker tag "$FULL_IMAGE_NAME" "${REGISTRY_URL}/${ECR_REPO}:latest"
  else
    docker tag "$FULL_IMAGE_NAME" "${DOCKER_USERNAME}/${DOCKER_REPO}:latest"
  fi
fi

# ------------------------------------------------------------------------------
# Push Docker image
# ------------------------------------------------------------------------------
echo ""
echo "Pushing Docker image: $FULL_IMAGE_NAME ..."
docker push "$FULL_IMAGE_NAME"

if [ "$IMAGE_TAG" != "latest" ]; then
  if [ "$REGISTRY_CHOICE" = "1" ]; then
    docker push "${REGISTRY_URL}/${ECR_REPO}:latest"
  else
    docker push "${DOCKER_USERNAME}/${DOCKER_REPO}:latest"
  fi
fi

echo ""
echo "=============================================="
echo "  Build & Push Complete!"
echo "  Image: $FULL_IMAGE_NAME"
echo "=============================================="
