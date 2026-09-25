@echo off
setlocal enabledelayedexpansion

rem =============================================================================
rem build-push.bat — Build and push the dashboard-app Docker image (Windows)
rem Supports: AWS ECR and Docker Hub
rem Usage: scripts\build-push.bat  (run from repository root)
rem =============================================================================

set "PROJECT_NAME=dashboard-app"
set "DOCKERFILE_PATH=Dockerfile"

echo ==============================================
echo   dashboard-app -- Docker Build ^& Push
echo ==============================================
echo.

rem ------------------------------------------------------------------------------
rem Sanitize image name using PowerShell
rem ------------------------------------------------------------------------------
for /f "delims=" %%i in ('powershell -NoProfile -Command "$n = 'dashboard-app'.ToLower() -replace '[^a-z0-9]','-'; $n = $n.Trim('-'); Write-Output $n"') do set "IMAGE_NAME=%%i"

rem ------------------------------------------------------------------------------
rem Prompt for image tag
rem ------------------------------------------------------------------------------
set /p "IMAGE_TAG_INPUT=Enter image tag [latest]: "
if "!IMAGE_TAG_INPUT!"=="" set "IMAGE_TAG_INPUT=latest"
for /f "delims=" %%i in ('powershell -NoProfile -Command "$t = '!IMAGE_TAG_INPUT!'.ToLower() -replace '[^a-z0-9._-]','-'; $t = $t.Trim('-'); if ($t -eq '') { $t = 'latest' }; Write-Output $t"') do set "IMAGE_TAG=%%i"
echo Image tag: !IMAGE_TAG!
echo.

rem ------------------------------------------------------------------------------
rem Registry selection
rem ------------------------------------------------------------------------------
echo Select container registry:
echo   1. AWS ECR
echo   2. Docker Hub
set /p "REGISTRY_CHOICE=Enter choice [1]: "
if "!REGISTRY_CHOICE!"=="" set "REGISTRY_CHOICE=1"

if "!REGISTRY_CHOICE!"=="1" goto :ecr_setup
if "!REGISTRY_CHOICE!"=="2" goto :dockerhub_setup
echo ERROR: Invalid registry choice '!REGISTRY_CHOICE!'. Exiting.
exit /b 1

rem ------------------------------------------------------------------------------
rem AWS ECR
rem ------------------------------------------------------------------------------
:ecr_setup
echo.
echo --- AWS ECR Configuration ---
set /p "AWS_REGION=Enter AWS Region [us-east-1]: "
if "!AWS_REGION!"=="" set "AWS_REGION=us-east-1"

echo Retrieving AWS Account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set "ACCOUNT_ID=%%i"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to retrieve AWS Account ID. Check AWS CLI configuration.
    exit /b 1
)
echo AWS Account ID: !ACCOUNT_ID!

set "ECR_REPO=!IMAGE_NAME!"
set "REGISTRY_URL=!ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

echo.
echo Logging in to Amazon ECR...
aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
if !ERRORLEVEL! neq 0 (
    echo ERROR: ECR login failed.
    exit /b 1
)

echo Checking ECR repository: !ECR_REPO! ...
aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo Creating ECR repository: !ECR_REPO! ...
    aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECR repository.
        exit /b 1
    )
)
echo ECR repository ready: !ECR_REPO!
goto :build

rem ------------------------------------------------------------------------------
rem Docker Hub
rem ------------------------------------------------------------------------------
:dockerhub_setup
echo.
echo --- Docker Hub Configuration ---
set /p "DOCKER_USERNAME=Enter Docker Hub username: "
set /p "DOCKER_PASSWORD=Enter Docker Hub password/token: "
set /p "DOCKER_REPO_INPUT=Enter Docker Hub repository name [!IMAGE_NAME!]: "
if "!DOCKER_REPO_INPUT!"=="" set "DOCKER_REPO_INPUT=!IMAGE_NAME!"
set "DOCKER_REPO=!DOCKER_REPO_INPUT!"

set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!DOCKER_REPO!:!IMAGE_TAG!"

echo Logging in to Docker Hub...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker Hub login failed.
    exit /b 1
)
goto :build

rem ------------------------------------------------------------------------------
rem Build Docker image
rem ------------------------------------------------------------------------------
:build
echo.
echo Full image name: !FULL_IMAGE_NAME!
echo.
echo Building Docker image...
docker build -f "!DOCKERFILE_PATH!" -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)
echo Docker image built successfully.

rem Tag as latest if a specific tag was provided
if not "!IMAGE_TAG!"=="latest" (
    if "!REGISTRY_CHOICE!"=="1" (
        docker tag "!FULL_IMAGE_NAME!" "!REGISTRY_URL!/!ECR_REPO!:latest"
    ) else (
        docker tag "!FULL_IMAGE_NAME!" "!DOCKER_USERNAME!/!DOCKER_REPO!:latest"
    )
)

rem ------------------------------------------------------------------------------
rem Push Docker image
rem ------------------------------------------------------------------------------
echo.
echo Pushing Docker image: !FULL_IMAGE_NAME! ...
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed.
    exit /b 1
)

if not "!IMAGE_TAG!"=="latest" (
    if "!REGISTRY_CHOICE!"=="1" (
        docker push "!REGISTRY_URL!/!ECR_REPO!:latest"
    ) else (
        docker push "!DOCKER_USERNAME!/!DOCKER_REPO!:latest"
    )
)

echo.
echo ==============================================
echo   Build ^& Push Complete!
echo   Image: !FULL_IMAGE_NAME!
echo ==============================================

endlocal
exit /b 0
