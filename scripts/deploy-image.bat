@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM deploy-image.bat — Deploy dashboard-app to Azure AKS (Windows)
REM Usage: scripts\deploy-image.bat
REM Run from repository root directory
REM Prerequisites: azure-cli, kubectl
REM =============================================================================

set "APP_NAME=dashboard-app"
set "NAMESPACE=dashboard-app"

echo ==============================================
echo   Deploy %APP_NAME% to Azure AKS
echo ==============================================
echo.

REM Prompt for Azure resource group
set /p "RESOURCE_GROUP=Enter Azure Resource Group name: "
if "!RESOURCE_GROUP!"=="" (
    echo ERROR: Resource group cannot be empty.
    exit /b 1
)

REM Prompt for AKS cluster name
set /p "CLUSTER_NAME=Enter AKS Cluster name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: AKS cluster name cannot be empty.
    exit /b 1
)

REM Prompt for Docker image URI
set /p "IMAGE_URI=Enter full Docker image URI (e.g. myregistry.azurecr.io/dashboard-app:latest): "
if "!IMAGE_URI!"=="" (
    echo ERROR: Image URI cannot be empty.
    exit /b 1
)

echo.
echo --- Configuration ---
echo   Resource Group : !RESOURCE_GROUP!
echo   AKS Cluster    : !CLUSTER_NAME!
echo   Image URI      : !IMAGE_URI!
echo   Namespace      : !NAMESPACE!
echo.

REM Configure kubectl credentials for AKS
echo Configuring kubectl for AKS cluster: !CLUSTER_NAME! ...
az aks get-credentials --resource-group "!RESOURCE_GROUP!" --name "!CLUSTER_NAME!" --overwrite-existing
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to get AKS credentials.
    exit /b 1
)

REM Verify cluster connectivity
echo Verifying cluster connectivity ...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to Kubernetes cluster.
    exit /b 1
)
echo.

REM Update deployment manifest with actual image URI using PowerShell
echo Updating Kubernetes manifests with image URI ...
powershell -NoProfile -Command "(Get-Content 'kubernetes\deployment.yaml') -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content 'kubernetes\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update deployment manifest.
    exit /b 1
)

REM Apply manifests in order
echo Applying Kubernetes manifests ...

echo   [1/4] Applying namespace ...
kubectl apply -f kubernetes\namespace.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply namespace.
    exit /b 1
)

echo   [2/4] Applying deployment ...
kubectl apply -f kubernetes\deployment.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply deployment.
    exit /b 1
)

echo   [3/4] Applying service ...
kubectl apply -f kubernetes\service.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply service.
    exit /b 1
)

echo   [4/4] Applying ingress ...
kubectl apply -f kubernetes\ingress.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply ingress.
    exit /b 1
)

echo.
echo Waiting for deployment rollout ...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo ERROR: Deployment rollout failed. Running rollback ...
    kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    echo Rollback initiated. Check pod status with: kubectl get pods -n !NAMESPACE!
    exit /b 1
)

echo.
echo Verifying deployed resources ...
kubectl get pods,svc,ingress -n !NAMESPACE!

echo.
echo ==============================================
echo   Deployment successful!
echo   Application URL: http://dashboard-app.example.com
echo   Health Check   : http://dashboard-app.example.com/api/health
echo ==============================================
echo.
echo Useful commands:
echo   kubectl get pods -n !NAMESPACE!
echo   kubectl logs -l app=!APP_NAME! -n !NAMESPACE!
echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

endlocal
