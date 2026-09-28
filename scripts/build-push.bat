@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM build-push.bat — Build and push Docker image for dashboard-app (Windows)
REM Usage: scripts\build-push.bat
REM Run from repository root directory
REM =============================================================================

set "PROJECT_NAME=dashboard-app"

REM Sanitize image name: lowercase, replace non-alphanumeric with hyphen
for /f "delims=" %%i in ('powershell -NoProfile -Command "\"dashboard-app\" -replace '[^a-z0-9]','-' -replace '^-+','' -replace '-+$',''"') do set "IMAGE_NAME=%%i"

echo ==============================================
echo   Build ^& Push: %PROJECT_NAME%
echo ==============================================
echo.

REM Prompt for image tag
set /p "IMAGE_TAG_INPUT=Enter image tag (press Enter for 'latest'): "
if "!IMAGE_TAG_INPUT!"=="" (
    set "IMAGE_TAG=latest"
) else (
    for /f "delims=" %%t in ('powershell -NoProfile -Command "\"!IMAGE_TAG_INPUT!\" -replace '[^a-z0-9._-]','-' -replace '^-+','' -replace '-+$','' -replace '([A-Z])','$1'.ToLower()"') do set "IMAGE_TAG=%%t"
    if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
)
echo Using tag: !IMAGE_TAG!
echo.

REM Registry selection
echo Select container registry:
echo   1. Azure Container Registry (ACR)
echo   2. Docker Hub
set /p "REGISTRY_CHOICE=Enter choice [1-2]: "

if "!REGISTRY_CHOICE!"=="1" (
    echo.
    echo --- Azure Container Registry ---
    set /p "ACR_NAME=Enter ACR name (e.g. myregistry): "
    if "!ACR_NAME!"=="" (
        echo ERROR: ACR name cannot be empty.
        exit /b 1
    )
    for /f "delims=" %%a in ('powershell -NoProfile -Command "\"!ACR_NAME!\" -replace '[^a-z0-9]','' -replace '([A-Z])','$1'.ToLower()"') do set "ACR_NAME_CLEAN=%%a"
    set "REGISTRY=!ACR_NAME_CLEAN!.azurecr.io"
    set "FULL_IMAGE_NAME=!REGISTRY!/!IMAGE_NAME!:!IMAGE_TAG!"

    echo Logging in to ACR: !ACR_NAME_CLEAN! ...
    az acr login --name !ACR_NAME_CLEAN!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: ACR login failed.
        exit /b 1
    )
) else if "!REGISTRY_CHOICE!"=="2" (
    echo.
    echo --- Docker Hub ---
    set /p "DOCKER_USERNAME=Enter Docker Hub username: "
    set /p "DOCKER_PASSWORD=Enter Docker Hub password/token: "
    if "!DOCKER_USERNAME!"=="" (
        echo ERROR: Docker Hub username cannot be empty.
        exit /b 1
    )
    if "!DOCKER_PASSWORD!"=="" (
        echo ERROR: Docker Hub password cannot be empty.
        exit /b 1
    )
    set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"

    echo Logging in to Docker Hub ...
    echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Docker Hub login failed.
        exit /b 1
    )
) else (
    echo ERROR: Invalid choice. Please enter 1 or 2.
    exit /b 1
)

echo.
echo Building Docker image: !FULL_IMAGE_NAME!
echo Build context: . (repository root)
docker build -f Dockerfile --target production -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)
echo Build successful.

echo.
echo Pushing image: !FULL_IMAGE_NAME! ...
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
