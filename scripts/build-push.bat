@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM build-push.bat - Build and push the dashboard-app Docker image (Windows)
REM Supports: AWS ECR and Docker Hub registries
REM Usage   : scripts\build-push.bat  (run from repository root)
REM =============================================================================

set "PROJECT_NAME=dashboard-app"
set "DOCKERFILE_PATH=Dockerfile"

echo ==============================================
echo   dashboard-app - Docker Build ^& Push
echo ==============================================
echo.

REM ---------------------------------------------------------------------------
REM Prompt for image tag
REM ---------------------------------------------------------------------------
set /p "IMAGE_TAG_INPUT=Enter image tag [latest]: "
if "!IMAGE_TAG_INPUT!"=="" (
    set "IMAGE_TAG=latest"
) else (
    set "IMAGE_TAG=!IMAGE_TAG_INPUT!"
)
echo Using image tag: !IMAGE_TAG!
echo.

REM ---------------------------------------------------------------------------
REM Registry selection
REM ---------------------------------------------------------------------------
echo Select container registry:
echo   1) AWS ECR
echo   2) Docker Hub
set /p "REGISTRY_CHOICE=Enter choice [1 or 2]: "
echo.

REM ---------------------------------------------------------------------------
REM AWS ECR flow
REM ---------------------------------------------------------------------------
if "!REGISTRY_CHOICE!"=="1" (
    set /p "AWS_REGION=Enter AWS Region (e.g. us-east-1): "
    set /p "AWS_ACCOUNT_ID=Enter AWS Account ID (12-digit): "
    set /p "ECR_REPO_INPUT=Enter ECR repository name [dashboard-app]: "
    if "!ECR_REPO_INPUT!"=="" (
        set "ECR_REPO=dashboard-app"
    ) else (
        set "ECR_REPO=!ECR_REPO_INPUT!"
    )

    set "REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
    set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

    echo.
    echo Authenticating with AWS ECR...
    aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: ECR login failed.
        exit /b 1
    )

    echo Ensuring ECR repository exists...
    aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        echo Creating ECR repository: !ECR_REPO!
        aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
        if !ERRORLEVEL! neq 0 (
            echo ERROR: Failed to create ECR repository.
            exit /b 1
        )
    )

REM ---------------------------------------------------------------------------
REM Docker Hub flow
REM ---------------------------------------------------------------------------
) else if "!REGISTRY_CHOICE!"=="2" (
    set /p "DOCKER_USERNAME=Enter Docker Hub username: "
    set /p "DOCKER_PASSWORD=Enter Docker Hub password/token: "
    set /p "DOCKER_NAMESPACE_INPUT=Enter Docker Hub namespace/org [leave blank to use username]: "
    if "!DOCKER_NAMESPACE_INPUT!"=="" (
        set "DOCKER_NAMESPACE=!DOCKER_USERNAME!"
    ) else (
        set "DOCKER_NAMESPACE=!DOCKER_NAMESPACE_INPUT!"
    )

    set "FULL_IMAGE_NAME=!DOCKER_NAMESPACE!/dashboard-app:!IMAGE_TAG!"

    echo.
    echo Authenticating with Docker Hub...
    echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Docker Hub login failed.
        exit /b 1
    )

) else (
    echo ERROR: Invalid registry choice. Please enter 1 or 2.
    exit /b 1
)

REM ---------------------------------------------------------------------------
REM Build Docker image
REM ---------------------------------------------------------------------------
echo.
echo Building Docker image: !FULL_IMAGE_NAME!
echo Build context: . (repository root)
docker build -f "!DOCKERFILE_PATH!" -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)

echo.
echo Pushing image: !FULL_IMAGE_NAME!
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed.
    exit /b 1
)

echo.
echo ==============================================
echo   Build ^& Push Complete!
echo   Image: !FULL_IMAGE_NAME!
echo ==============================================

endlocal
