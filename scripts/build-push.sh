#!/bin/bash
# =============================================================================
# build-push.sh — Build and push Docker image for dashboard-app
# Usage: ./scripts/build-push.sh
# =============================================================================
set -e
set -o pipefail

PROJECT_NAME="dashboard-app"
DOCKERFILE="Dockerfile"

echo "=============================================="
echo "  dashboard-app — Docker Build & Push"
echo "=============================================="
echo ""

# ── Sanitize image name ───────────────────────────────────────────────────────
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

# ── Prompt for image tag ──────────────────────────────────────────────────────
read -rp "Enter image tag [latest]: " IMAGE_TAG_INPUT
IMAGE_TAG=$(echo "${IMAGE_TAG_INPUT:-latest}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
if [ -z "$IMAGE_TAG" ]; then
  IMAGE_TAG="latest"
fi
echo "Image tag: $IMAGE_TAG"
echo ""

# ── Registry selection ────────────────────────────────────────────────────────
echo "Select container registry:"
echo "  1. AWS ECR"
echo "  2. Docker Hub"
read -rp "Enter choice [1]: " REGISTRY_CHOICE
REGISTRY_CHOICE="${REGISTRY_CHOICE:-1}"

if [ "$REGISTRY_CHOICE" = "1" ]; then
  # ── AWS ECR ──────────────────────────────────────────────────────────────
  echo ""
  echo "--- AWS ECR Configuration ---"
  read -rp "Enter AWS Region [us-east-1]: " AWS_REGION
  AWS_REGION="${AWS_REGION:-us-east-1}"

  read -rp "Enter AWS Account ID: " AWS_ACCOUNT_ID
  if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "ERROR: AWS Account ID is required." >&2
    exit 1
  fi

  ECR_REPO="${IMAGE_NAME}"
  REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

  echo ""
  echo "Authenticating with AWS ECR..."
  aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$REGISTRY_URL"
  echo "ECR login successful."

  # Auto-create ECR repository if it does not exist
  echo "Checking ECR repository '${ECR_REPO}'..."
  aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
  echo "ECR repository ready."

elif [ "$REGISTRY_CHOICE" = "2" ]; then
  # ── Docker Hub ────────────────────────────────────────────────────────────
  echo ""
  echo "--- Docker Hub Configuration ---"
  read -rp "Enter Docker Hub username: " DOCKER_USERNAME
  if [ -z "$DOCKER_USERNAME" ]; then
    echo "ERROR: Docker Hub username is required." >&2
    exit 1
  fi

  read -rsp "Enter Docker Hub password/token: " DOCKER_PASSWORD
  echo ""
  if [ -z "$DOCKER_PASSWORD" ]; then
    echo "ERROR: Docker Hub password/token is required." >&2
    exit 1
  fi

  FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

  echo "Authenticating with Docker Hub..."
  echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
  echo "Docker Hub login successful."

else
  echo "ERROR: Invalid registry choice '${REGISTRY_CHOICE}'." >&2
  exit 1
fi

# ── Build Docker image ────────────────────────────────────────────────────────
echo ""
echo "Building Docker image: ${FULL_IMAGE_NAME}"
echo "Build context: . (repository root)"
docker build -f "${DOCKERFILE}" -t "${FULL_IMAGE_NAME}" .
echo "Docker build successful."

# ── Push Docker image ─────────────────────────────────────────────────────────
echo ""
echo "Pushing image: ${FULL_IMAGE_NAME}"
docker push "${FULL_IMAGE_NAME}"
echo ""
echo "=============================================="
echo "  Image pushed successfully!"
echo "  ${FULL_IMAGE_NAME}"
echo "=============================================="
