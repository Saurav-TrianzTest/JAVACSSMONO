@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: build-push.bat — Build and push Docker image for dashboard-app (Windows)
:: Usage: scripts\build-push.bat
:: =============================================================================

set "PROJECT_NAME=dashboard-app"
set "DOCKERFILE=Dockerfile"

echo ==============================================
echo   dashboard-app -- Docker Build ^& Push
echo ==============================================
echo.

:: ── Sanitize image name ───────────────────────────────────────────────────────
for /f "delims=" %%i in ('powershell -NoProfile -Command "\"dashboard-app\".ToLower() -replace '[^a-z0-9]','-' -replace '^-+','' -replace '-+$',''"') do set "IMAGE_NAME=%%i"

:: ── Prompt for image tag ──────────────────────────────────────────────────────
set /p "IMAGE_TAG_INPUT=Enter image tag [latest]: "
if "!IMAGE_TAG_INPUT!"=="" set "IMAGE_TAG_INPUT=latest"
for /f "delims=" %%i in ('powershell -NoProfile -Command "\"!IMAGE_TAG_INPUT!\".ToLower() -replace '[^a-z0-9._-]','-' -replace '^-+','' -replace '-+$',''"') do set "IMAGE_TAG=%%i"
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
echo Image tag: !IMAGE_TAG!
echo.

:: ── Registry selection ────────────────────────────────────────────────────────
echo Select container registry:
echo   1. AWS ECR
echo   2. Docker Hub
set /p "REGISTRY_CHOICE=Enter choice [1]: "
if "!REGISTRY_CHOICE!"=="" set "REGISTRY_CHOICE=1"

if "!REGISTRY_CHOICE!"=="1" goto :ecr_setup
if "!REGISTRY_CHOICE!"=="2" goto :dockerhub_setup
echo ERROR: Invalid registry choice '!REGISTRY_CHOICE!'.
exit /b 1

:ecr_setup
echo.
echo --- AWS ECR Configuration ---
set /p "AWS_REGION=Enter AWS Region [us-east-1]: "
if "!AWS_REGION!"=="" set "AWS_REGION=us-east-1"

set /p "AWS_ACCOUNT_ID=Enter AWS Account ID: "
if "!AWS_ACCOUNT_ID!"=="" (
    echo ERROR: AWS Account ID is required.
    exit /b 1
)

set "ECR_REPO=!IMAGE_NAME!"
set "REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

echo.
echo Authenticating with AWS ECR...
aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
if !ERRORLEVEL! neq 0 (
    echo ERROR: ECR login failed.
    exit /b 1
)
echo ECR login successful.

echo Checking ECR repository '!ECR_REPO!'...
aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Creating ECR repository...
    aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECR repository.
        exit /b 1
    )
)
echo ECR repository ready.
goto :build_image

:dockerhub_setup
echo.
echo --- Docker Hub Configuration ---
set /p "DOCKER_USERNAME=Enter Docker Hub username: "
if "!DOCKER_USERNAME!"=="" (
    echo ERROR: Docker Hub username is required.
    exit /b 1
)

set /p "DOCKER_PASSWORD=Enter Docker Hub password/token: "
if "!DOCKER_PASSWORD!"=="" (
    echo ERROR: Docker Hub password/token is required.
    exit /b 1
)

set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"

echo Authenticating with Docker Hub...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker Hub login failed.
    exit /b 1
)
echo Docker Hub login successful.
goto :build_image

:build_image
echo.
echo Building Docker image: !FULL_IMAGE_NAME!
echo Build context: . (repository root)
docker build -f "!DOCKERFILE!" -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)
echo Docker build successful.

echo.
echo Pushing image: !FULL_IMAGE_NAME!
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed.
    exit /b 1
)

echo.
echo ==============================================
echo   Image pushed successfully!
echo   !FULL_IMAGE_NAME!
echo ==============================================

endlocal
