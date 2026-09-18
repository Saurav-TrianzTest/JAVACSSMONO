#!/usr/bin/env bash
# =============================================================================
# build-push.sh — Build and Push Docker Image
# Application: dashboard-app (Spring Boot 3.2.5 / Java 17)
# Target Registry: AWS ECR or Docker Hub (interactive selection)
# =============================================================================
set -e
set -o pipefail

# -----------------------------------------------------------------------------
# Colour helpers
# -----------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
echo ""
echo "============================================================"
echo "  dashboard-app — Docker Build & Push"
echo "  Spring Boot 3.2.5 / Java 17 / AWS ECS Fargate"
echo "============================================================"
echo ""

# -----------------------------------------------------------------------------
# Sanitise project name → valid Docker image name
# Lowercase, replace non-alphanumeric with hyphens, trim leading/trailing hyphens
# -----------------------------------------------------------------------------
PROJECT_NAME="dashboard-app"
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')
info "Project name  : $PROJECT_NAME"
info "Image name    : $IMAGE_NAME"

# -----------------------------------------------------------------------------
# Prompt for image tag
# -----------------------------------------------------------------------------
echo ""
read -rp "Enter image tag [default: latest]: " RAW_TAG
if [ -z "$RAW_TAG" ]; then
  IMAGE_TAG="latest"
else
  IMAGE_TAG=$(echo "$RAW_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//')
  if [ -z "$IMAGE_TAG" ]; then
    IMAGE_TAG="latest"
    warn "Tag sanitised to empty — defaulting to 'latest'"
  fi
fi
info "Image tag     : $IMAGE_TAG"

# -----------------------------------------------------------------------------
# Registry selection
# -----------------------------------------------------------------------------
echo ""
echo "Select target registry:"
echo "  1) AWS ECR (Elastic Container Registry)"
echo "  2) Docker Hub"
echo ""
read -rp "Enter choice [1 or 2]: " REGISTRY_CHOICE

# =============================================================================
# AWS ECR
# =============================================================================
if [ "$REGISTRY_CHOICE" = "1" ]; then
  echo ""
  info "=== AWS ECR Configuration ==="
  read -rp "AWS Region (e.g. us-east-1): " AWS_REGION
  read -rp "AWS Account ID (12 digits)  : " AWS_ACCOUNT_ID
  read -rp "ECR Repository name         [default: ${IMAGE_NAME}]: " ECR_REPO_INPUT
  ECR_REPO="${ECR_REPO_INPUT:-$IMAGE_NAME}"

  REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

  echo ""
  info "Registry URL  : $REGISTRY_URL"
  info "Full image    : $FULL_IMAGE_NAME"

  # Authenticate with ECR
  echo ""
  info "Authenticating with Amazon ECR..."
  aws ecr get-login-password --region "$AWS_REGION" \
    | docker login --username AWS --password-stdin "$REGISTRY_URL"
  success "ECR authentication successful."

  # Auto-create ECR repository if it does not exist
  info "Checking ECR repository '${ECR_REPO}'..."
  aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" \
    > /dev/null 2>&1 \
    || {
      info "Repository not found — creating '${ECR_REPO}'..."
      aws ecr create-repository \
        --repository-name "$ECR_REPO" \
        --region "$AWS_REGION" \
        --image-scanning-configuration scanOnPush=true \
        --encryption-configuration encryptionType=AES256
      success "ECR repository '${ECR_REPO}' created."
    }
  success "ECR repository '${ECR_REPO}' is ready."

# =============================================================================
# Docker Hub
# =============================================================================
elif [ "$REGISTRY_CHOICE" = "2" ]; then
  echo ""
  info "=== Docker Hub Configuration ==="
  read -rp "Docker Hub username         : " DOCKER_USERNAME
  read -rsp "Docker Hub password/token  : " DOCKER_PASSWORD
  echo ""
  read -rp "Docker Hub namespace        [default: ${DOCKER_USERNAME}]: " DOCKER_NAMESPACE_INPUT
  DOCKER_NAMESPACE="${DOCKER_NAMESPACE_INPUT:-$DOCKER_USERNAME}"

  FULL_IMAGE_NAME="${DOCKER_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"

  echo ""
  info "Full image    : $FULL_IMAGE_NAME"

  # Authenticate with Docker Hub
  info "Authenticating with Docker Hub..."
  echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
  success "Docker Hub authentication successful."

else
  error "Invalid choice '${REGISTRY_CHOICE}'. Please enter 1 or 2."
  exit 1
fi

# =============================================================================
# Build Docker image
# =============================================================================
echo ""
info "Building Docker image..."
info "Build context : . (project root)"
info "Dockerfile    : Dockerfile"
echo ""

docker build \
  --file Dockerfile \
  --tag "$FULL_IMAGE_NAME" \
  --label "app.name=dashboard-app" \
  --label "app.version=${IMAGE_TAG}" \
  --label "build.timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  .

success "Docker image built: $FULL_IMAGE_NAME"

# =============================================================================
# Push Docker image
# =============================================================================
echo ""
info "Pushing image to registry..."
docker push "$FULL_IMAGE_NAME"
success "Image pushed: $FULL_IMAGE_NAME"

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================================"
success "Build and push complete!"
echo "  Image : $FULL_IMAGE_NAME"
echo "============================================================"
echo ""
info "Next step: run scripts/deploy-image.sh to deploy to AWS ECS Fargate."
echo ""
