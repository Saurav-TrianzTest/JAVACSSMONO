#!/bin/bash
set -e

# =============================================================================
# build-push.sh — Build and push Docker image for dashboard-app
# Usage: ./scripts/build-push.sh
# Run from repository root directory
# =============================================================================

PROJECT_NAME="dashboard-app"
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "=============================================="
echo "  Build & Push: $PROJECT_NAME"
echo "=============================================="
echo ""

# Prompt for image tag
read -rp "Enter image tag (press Enter for 'latest'): " IMAGE_TAG_INPUT
IMAGE_TAG=$(echo "$IMAGE_TAG_INPUT" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
if [ -z "$IMAGE_TAG" ]; then
  IMAGE_TAG="latest"
fi
echo "Using tag: $IMAGE_TAG"
echo ""

# Registry selection
echo "Select container registry:"
echo "  1. Azure Container Registry (ACR)"
echo "  2. Docker Hub"
read -rp "Enter choice [1-2]: " REGISTRY_CHOICE

case "$REGISTRY_CHOICE" in
  1)
    echo ""
    echo "--- Azure Container Registry ---"
    read -rp "Enter ACR name (e.g. myregistry): " ACR_NAME
    ACR_NAME=$(echo "$ACR_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]//g')
    if [ -z "$ACR_NAME" ]; then
      echo "ERROR: ACR name cannot be empty." >&2
      exit 1
    fi
    REGISTRY="${ACR_NAME}.azurecr.io"
    FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

    echo "Logging in to ACR: $ACR_NAME ..."
    az acr login --name "$ACR_NAME"
    if [ $? -ne 0 ]; then
      echo "ERROR: ACR login failed." >&2
      exit 1
    fi
    ;;
  2)
    echo ""
    echo "--- Docker Hub ---"
    read -rp "Enter Docker Hub username: " DOCKER_USERNAME
    read -rsp "Enter Docker Hub password/token: " DOCKER_PASSWORD
    echo ""
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
      echo "ERROR: Docker Hub username and password cannot be empty." >&2
      exit 1
    fi
    REGISTRY="docker.io"
    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

    echo "Logging in to Docker Hub ..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    if [ $? -ne 0 ]; then
      echo "ERROR: Docker Hub login failed." >&2
      exit 1
    fi
    ;;
  *)
    echo "ERROR: Invalid choice. Please enter 1 or 2." >&2
    exit 1
    ;;
esac

echo ""
echo "Building Docker image: $FULL_IMAGE_NAME"
echo "Build context: . (repository root)"
docker build -f Dockerfile --target production -t "$FULL_IMAGE_NAME" .
if [ $? -ne 0 ]; then
  echo "ERROR: Docker build failed." >&2
  exit 1
fi
echo "Build successful."

echo ""
echo "Pushing image: $FULL_IMAGE_NAME ..."
docker push "$FULL_IMAGE_NAME"
if [ $? -ne 0 ]; then
  echo "ERROR: Docker push failed." >&2
  exit 1
fi

echo ""
echo "=============================================="
echo "  Image pushed successfully!"
echo "  $FULL_IMAGE_NAME"
echo "=============================================="
