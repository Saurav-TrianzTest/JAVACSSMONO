@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: deploy-image.bat — Deploy dashboard-app to Azure AKS (Windows)
:: Usage: scripts\deploy-image.bat
:: =============================================================================

set "APP_NAME=dashboard-app"
set "NAMESPACE=dashboard-app"
set "MANIFEST_DIR=kubernetes"

echo ==============================================
echo   dashboard-app -- Deploy to Azure AKS
echo ==============================================
echo.

:: ── Validate required tools ───────────────────────────────────────────────────
where az >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo ERROR: 'az' (Azure CLI) is not installed or not in PATH.
    exit /b 1
)
where kubectl >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo ERROR: 'kubectl' is not installed or not in PATH.
    exit /b 1
)

:: ── Prompt for Azure details ──────────────────────────────────────────────────
set /p "RESOURCE_GROUP=Enter Azure Resource Group name: "
if "!RESOURCE_GROUP!"=="" (
    echo ERROR: Resource group cannot be empty.
    exit /b 1
)

set /p "CLUSTER_NAME=Enter AKS Cluster name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: AKS cluster name cannot be empty.
    exit /b 1
)

:: ── Prompt for Docker image URI ───────────────────────────────────────────────
set /p "IMAGE_URI=Enter full Docker image URI (e.g. myregistry.azurecr.io/dashboard-app:latest): "
if "!IMAGE_URI!"=="" (
    echo ERROR: Image URI cannot be empty.
    exit /b 1
)

echo.
echo Configuration:
echo   Resource Group : !RESOURCE_GROUP!
echo   AKS Cluster    : !CLUSTER_NAME!
echo   Image URI      : !IMAGE_URI!
echo   Namespace      : !NAMESPACE!
echo.

:: ── Configure kubectl ─────────────────────────────────────────────────────────
echo Configuring kubectl for AKS cluster ...
az aks get-credentials --resource-group !RESOURCE_GROUP! --name !CLUSTER_NAME! --overwrite-existing
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to configure kubectl for AKS cluster.
    exit /b 1
)
echo kubectl configured successfully.
echo.

:: ── Verify cluster connectivity ───────────────────────────────────────────────
echo Verifying cluster connectivity ...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to AKS cluster.
    exit /b 1
)
echo.

:: ── Patch manifests with actual image URI ────────────────────────────────────
echo Updating Kubernetes manifests ...
powershell -NoProfile -Command ^
  "(Get-Content '!MANIFEST_DIR!\deployment.yaml') -replace '\{\{IMAGE_URI\}\}', '!IMAGE_URI!' | Set-Content '!MANIFEST_DIR!\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update deployment.yaml with image URI.
    exit /b 1
)
echo   deployment.yaml updated with image: !IMAGE_URI!
echo.

:: ── Apply manifests in order ──────────────────────────────────────────────────
echo Applying Kubernetes manifests ...

echo   [1/4] Applying namespace ...
kubectl apply -f !MANIFEST_DIR!\namespace.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply namespace.yaml.
    exit /b 1
)

echo   [2/4] Applying deployment ...
kubectl apply -f !MANIFEST_DIR!\deployment.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply deployment.yaml.
    exit /b 1
)

echo   [3/4] Applying service ...
kubectl apply -f !MANIFEST_DIR!\service.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply service.yaml.
    exit /b 1
)

echo   [4/4] Applying ingress ...
kubectl apply -f !MANIFEST_DIR!\ingress.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply ingress.yaml.
    exit /b 1
)
echo.

:: ── Wait for rollout ──────────────────────────────────────────────────────────
echo Waiting for deployment rollout ...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo ERROR: Deployment rollout failed or timed out.
    echo Rollback command: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    exit /b 1
)
echo Deployment rollout complete.
echo.

:: ── Verify resources ──────────────────────────────────────────────────────────
echo Verifying deployed resources ...
kubectl get pods,svc,ingress -n !NAMESPACE!
echo.

echo ==============================================
echo   Deployment complete!
echo   Application URL: http://dashboard-app.example.com
echo   Health check   : http://dashboard-app.example.com/api/health
echo.
echo   Rollback command (if needed):
echo     kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
echo ==============================================

endlocal
