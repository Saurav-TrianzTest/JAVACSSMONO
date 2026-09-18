@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: build-push.bat — Build and Push Docker Image (Windows)
:: Application: dashboard-app (Spring Boot 3.2.5 / Java 17)
:: Target Registry: AWS ECR or Docker Hub (interactive selection)
:: =============================================================================

echo.
echo ============================================================
echo   dashboard-app -- Docker Build ^& Push
echo   Spring Boot 3.2.5 / Java 17 / AWS ECS Fargate
echo ============================================================
echo.

:: -----------------------------------------------------------------------------
:: Sanitise project name using PowerShell
:: -----------------------------------------------------------------------------
set "PROJECT_NAME=dashboard-app"
for /f "delims=" %%i in ('powershell -NoProfile -Command "$n = 'dashboard-app'.ToLower() -replace '[^a-z0-9]','-'; $n = $n.Trim('-'); Write-Output $n"') do set "IMAGE_NAME=%%i"
echo [INFO]  Project name  : %PROJECT_NAME%
echo [INFO]  Image name    : %IMAGE_NAME%

:: -----------------------------------------------------------------------------
:: Prompt for image tag
:: -----------------------------------------------------------------------------
echo.
set /p "RAW_TAG=Enter image tag [default: latest]: "
if "!RAW_TAG!"=="" (
    set "IMAGE_TAG=latest"
) else (
    for /f "delims=" %%i in ('powershell -NoProfile -Command "$t = '!RAW_TAG!'.ToLower() -replace '[^a-z0-9._-]','-'; $t = $t.Trim('-'); if ($t -eq '') { 'latest' } else { $t }"') do set "IMAGE_TAG=%%i"
)
echo [INFO]  Image tag     : !IMAGE_TAG!

:: -----------------------------------------------------------------------------
:: Registry selection
:: -----------------------------------------------------------------------------
echo.
echo Select target registry:
echo   1) AWS ECR (Elastic Container Registry)
echo   2) Docker Hub
echo.
set /p "REGISTRY_CHOICE=Enter choice [1 or 2]: "

:: =============================================================================
:: AWS ECR
:: =============================================================================
if "!REGISTRY_CHOICE!"=="1" (
    echo.
    echo [INFO]  === AWS ECR Configuration ===
    set /p "AWS_REGION=AWS Region (e.g. us-east-1): "
    set /p "AWS_ACCOUNT_ID=AWS Account ID (12 digits)  : "
    set /p "ECR_REPO_INPUT=ECR Repository name [default: !IMAGE_NAME!]: "
    if "!ECR_REPO_INPUT!"=="" (
        set "ECR_REPO=!IMAGE_NAME!"
    ) else (
        set "ECR_REPO=!ECR_REPO_INPUT!"
    )

    set "REGISTRY_URL=!AWS_ACCOUNT_ID!.dkr.ecr.!AWS_REGION!.amazonaws.com"
    set "FULL_IMAGE_NAME=!REGISTRY_URL!/!ECR_REPO!:!IMAGE_TAG!"

    echo.
    echo [INFO]  Registry URL  : !REGISTRY_URL!
    echo [INFO]  Full image    : !FULL_IMAGE_NAME!

    :: Authenticate with ECR
    echo.
    echo [INFO]  Authenticating with Amazon ECR...
    aws ecr get-login-password --region !AWS_REGION! | docker login --username AWS --password-stdin !REGISTRY_URL!
    if !ERRORLEVEL! neq 0 (
        echo [ERROR] ECR authentication failed.
        exit /b 1
    )
    echo [OK]    ECR authentication successful.

    :: Auto-create ECR repository if it does not exist
    echo [INFO]  Checking ECR repository '!ECR_REPO!'...
    aws ecr describe-repositories --repository-names !ECR_REPO! --region !AWS_REGION! >nul 2>&1
    if !ERRORLEVEL! neq 0 (
        echo [INFO]  Repository not found -- creating '!ECR_REPO!'...
        aws ecr create-repository --repository-name !ECR_REPO! --region !AWS_REGION! --image-scanning-configuration scanOnPush=true --encryption-configuration encryptionType=AES256
        if !ERRORLEVEL! neq 0 (
            echo [ERROR] Failed to create ECR repository '!ECR_REPO!'.
            exit /b 1
        )
        echo [OK]    ECR repository '!ECR_REPO!' created.
    ) else (
        echo [OK]    ECR repository '!ECR_REPO!' already exists.
    )

:: =============================================================================
:: Docker Hub
:: =============================================================================
) else if "!REGISTRY_CHOICE!"=="2" (
    echo.
    echo [INFO]  === Docker Hub Configuration ===
    set /p "DOCKER_USERNAME=Docker Hub username         : "
    set /p "DOCKER_PASSWORD=Docker Hub password/token   : "
    set /p "DOCKER_NAMESPACE_INPUT=Docker Hub namespace [default: !DOCKER_USERNAME!]: "
    if "!DOCKER_NAMESPACE_INPUT!"=="" (
        set "DOCKER_NAMESPACE=!DOCKER_USERNAME!"
    ) else (
        set "DOCKER_NAMESPACE=!DOCKER_NAMESPACE_INPUT!"
    )

    set "FULL_IMAGE_NAME=!DOCKER_NAMESPACE!/!IMAGE_NAME!:!IMAGE_TAG!"

    echo.
    echo [INFO]  Full image    : !FULL_IMAGE_NAME!

    :: Authenticate with Docker Hub
    echo [INFO]  Authenticating with Docker Hub...
    echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
    if !ERRORLEVEL! neq 0 (
        echo [ERROR] Docker Hub authentication failed.
        exit /b 1
    )
    echo [OK]    Docker Hub authentication successful.

) else (
    echo [ERROR] Invalid choice '!REGISTRY_CHOICE!'. Please enter 1 or 2.
    exit /b 1
)

:: =============================================================================
:: Build Docker image
:: =============================================================================
echo.
echo [INFO]  Building Docker image...
echo [INFO]  Build context : . (project root)
echo [INFO]  Dockerfile    : Dockerfile
echo.

docker build --file Dockerfile --tag "!FULL_IMAGE_NAME!" --label "app.name=dashboard-app" --label "app.version=!IMAGE_TAG!" .
if !ERRORLEVEL! neq 0 (
    echo [ERROR] Docker build failed.
    exit /b 1
)
echo [OK]    Docker image built: !FULL_IMAGE_NAME!

:: =============================================================================
:: Push Docker image
:: =============================================================================
echo.
echo [INFO]  Pushing image to registry...
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
    echo [ERROR] Docker push failed.
    exit /b 1
)
echo [OK]    Image pushed: !FULL_IMAGE_NAME!

:: =============================================================================
:: Summary
:: =============================================================================
echo.
echo ============================================================
echo [OK]    Build and push complete!
echo   Image : !FULL_IMAGE_NAME!
echo ============================================================
echo.
echo [INFO]  Next step: run scripts\deploy-image.bat to deploy to AWS ECS Fargate.
echo.

endlocal
