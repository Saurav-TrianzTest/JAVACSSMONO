@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: build-push.bat — Build and push the dashboard-app Docker image (Windows)
:: Supports: Azure Container Registry (ACR) and Docker Hub
:: Usage   : scripts\build-push.bat
:: =============================================================================

set "PROJECT_NAME=dashboard-app"

echo ==============================================
echo   dashboard-app -- Docker Build ^& Push
echo ==============================================
echo.

:: ── Sanitize image name (lowercase, hyphens only) ────────────────────────────
for /f "delims=" %%i in ('powershell -NoProfile -Command "$n = '%PROJECT_NAME%'.ToLower() -replace '[^a-z0-9]+','-'; $n.Trim('-')"') do set "IMAGE_NAME=%%i"

:: ── Prompt for image tag ──────────────────────────────────────────────────────
set /p "INPUT_TAG=Enter image tag [latest]: "
if "!INPUT_TAG!"=="" set "INPUT_TAG=latest"
for /f "delims=" %%i in ('powershell -NoProfile -Command "$t = '!INPUT_TAG!'.ToLower() -replace '[^a-z0-9._-]+','-'; $t.Trim('-')"') do set "IMAGE_TAG=%%i"
if "!IMAGE_TAG!"=="" set "IMAGE_TAG=latest"
echo Using image tag: !IMAGE_TAG!
echo.

:: ── Registry selection ────────────────────────────────────────────────────────
echo Select container registry:
echo   1) Azure Container Registry (ACR)
echo   2) Docker Hub
set /p "REGISTRY_CHOICE=Enter choice [1]: "
if "!REGISTRY_CHOICE!"=="" set "REGISTRY_CHOICE=1"

if "!REGISTRY_CHOICE!"=="1" goto :acr_login
if "!REGISTRY_CHOICE!"=="2" goto :dockerhub_login
echo ERROR: Invalid choice '!REGISTRY_CHOICE!'. Please enter 1 or 2.
exit /b 1

:acr_login
echo.
echo -- Azure Container Registry ------------------
set /p "ACR_NAME=Enter ACR name (e.g. myregistry): "
if "!ACR_NAME!"=="" (
    echo ERROR: ACR name cannot be empty.
    exit /b 1
)
set "REGISTRY=!ACR_NAME!.azurecr.io"
set "FULL_IMAGE_NAME=!REGISTRY!/!IMAGE_NAME!:!IMAGE_TAG!"

echo.
echo Logging in to ACR: !ACR_NAME! ...
az acr login --name !ACR_NAME!
if !ERRORLEVEL! neq 0 (
    echo ERROR: ACR login failed.
    exit /b 1
)
goto :build

:dockerhub_login
echo.
echo -- Docker Hub --------------------------------
set /p "DOCKER_USERNAME=Enter Docker Hub username: "
if "!DOCKER_USERNAME!"=="" (
    echo ERROR: Docker Hub username cannot be empty.
    exit /b 1
)
set /p "DOCKER_PASSWORD=Enter Docker Hub password/token: "
if "!DOCKER_PASSWORD!"=="" (
    echo ERROR: Docker Hub password cannot be empty.
    exit /b 1
)
set "FULL_IMAGE_NAME=!DOCKER_USERNAME!/!IMAGE_NAME!:!IMAGE_TAG!"

echo.
echo Logging in to Docker Hub ...
echo !DOCKER_PASSWORD! | docker login --username !DOCKER_USERNAME! --password-stdin
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker Hub login failed.
    exit /b 1
)
goto :build

:build
echo.
echo Building image: !FULL_IMAGE_NAME!
echo Build context : . (repository root)
echo ----------------------------------------------

docker build -f Dockerfile -t "!FULL_IMAGE_NAME!" .
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker build failed.
    exit /b 1
)

echo.
echo Pushing image: !FULL_IMAGE_NAME! ...
docker push "!FULL_IMAGE_NAME!"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Docker push failed.
    exit /b 1
)

echo.
echo ==============================================
echo   Build ^& Push complete!
echo   Image: !FULL_IMAGE_NAME!
echo ==============================================

endlocal
