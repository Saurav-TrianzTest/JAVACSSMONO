#!/usr/bin/env bash
# =============================================================================
# build-push.sh — Build and push Docker image for dashboard-app
# Platform: Linux / macOS
# Usage: ./scripts/build-push.sh
# Run from the repository root directory.
# =============================================================================
set -e
set -o pipefail

PROJECT_NAME="dashboard-app"
DOCKERFILE_PATH="Dockerfile"

echo "=============================================="
echo "  dashboard-app — Docker Build & Push"
echo "=============================================="
echo ""

# ── Tag sanitisation ──────────────────────────────────────────────────────────
# Lowercase, replace non-alphanumeric chars with hyphens, trim leading/trailing hyphens.
IMAGE_NAME=$(echo "${PROJECT_NAME}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "Project name  : ${PROJECT_NAME}"
echo "Image name    : ${IMAGE_NAME}"
echo ""

# ── Prompt for image tag ──────────────────────────────────────────────────────
read -rp "Enter image tag [latest]: " RAW_TAG
RAW_TAG="${RAW_TAG:-latest}"
IMAGE_TAG=$(echo "${RAW_TAG}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG="${IMAGE_TAG:-latest}"
echo "Image tag     : ${IMAGE_TAG}"
echo ""

# ── Registry selection ────────────────────────────────────────────────────────
echo "Select container registry:"
echo "  1) AWS ECR"
echo "  2) Docker Hub"
read -rp "Enter choice [1]: " REGISTRY_CHOICE
REGISTRY_CHOICE="${REGISTRY_CHOICE:-1}"

if [ "${REGISTRY_CHOICE}" = "1" ]; then
  # ── AWS ECR ──────────────────────────────────────────────────────────────
  echo ""
  echo "── AWS ECR Configuration ──────────────────────────────────────────────"
  read -rp "AWS Region [us-east-1]: " AWS_REGION
  AWS_REGION="${AWS_REGION:-us-east-1}"

  read -rp "AWS Account ID: " AWS_ACCOUNT_ID
  if [ -z "${AWS_ACCOUNT_ID}" ]; then
    echo "Fetching AWS Account ID from STS..."
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    echo "Account ID    : ${AWS_ACCOUNT_ID}"
  fi

  read -rp "ECR Repository name [${IMAGE_NAME}]: " ECR_REPO
  ECR_REPO="${ECR_REPO:-${IMAGE_NAME}}"

  REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

  echo ""
  echo "Logging in to ECR..."
  aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${REGISTRY_URL}"
  echo "ECR login successful."

  # Auto-create ECR repository if it does not exist
  echo "Checking ECR repository '${ECR_REPO}'..."
  aws ecr describe-repositories --repository-names "${ECR_REPO}" --region "${AWS_REGION}" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "${ECR_REPO}" --region "${AWS_REGION}"
  echo "ECR repository ready."

elif [ "${REGISTRY_CHOICE}" = "2" ]; then
  # ── Docker Hub ────────────────────────────────────────────────────────────
  echo ""
  echo "── Docker Hub Configuration ───────────────────────────────────────────"
  read -rp "Docker Hub username: " DOCKER_USERNAME
  read -rsp "Docker Hub password/token: " DOCKER_PASSWORD
  echo ""
  read -rp "Docker Hub namespace/org [${DOCKER_USERNAME}]: " DOCKER_NAMESPACE
  DOCKER_NAMESPACE="${DOCKER_NAMESPACE:-${DOCKER_USERNAME}}"

  FULL_IMAGE_NAME="${DOCKER_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"

  echo ""
  echo "Logging in to Docker Hub..."
  echo "${DOCKER_PASSWORD}" | docker login --username "${DOCKER_USERNAME}" --password-stdin
  echo "Docker Hub login successful."

else
  echo "ERROR: Invalid registry choice '${REGISTRY_CHOICE}'. Exiting."
  exit 1
fi

echo ""
echo "Full image    : ${FULL_IMAGE_NAME}"
echo ""

# ── Docker build ──────────────────────────────────────────────────────────────
echo "Building Docker image..."
echo "  docker build -f ${DOCKERFILE_PATH} -t ${FULL_IMAGE_NAME} ."
docker build -f "${DOCKERFILE_PATH}" -t "${FULL_IMAGE_NAME}" .
echo "Build successful."
echo ""

# ── Docker push ───────────────────────────────────────────────────────────────
echo "Pushing image to registry..."
docker push "${FULL_IMAGE_NAME}"
echo ""
echo "=============================================="
echo "  Image pushed successfully!"
echo "  ${FULL_IMAGE_NAME}"
echo "=============================================="
