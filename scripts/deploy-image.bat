@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: deploy-image.bat — Deploy dashboard-app to AWS EKS (Windows)
:: Usage: scripts\deploy-image.bat
:: =============================================================================

set "APP_NAME=dashboard-app"
set "NAMESPACE=dashboard-app"
set "K8S_DIR=kubernetes"

echo ==============================================
echo   dashboard-app -- AWS EKS Deployment
echo ==============================================
echo.

:: ── Prompt for AWS / EKS configuration ───────────────────────────────────────
set /p "AWS_REGION=Enter AWS Region [us-east-1]: "
if "!AWS_REGION!"=="" set "AWS_REGION=us-east-1"

set /p "CLUSTER_NAME=Enter EKS Cluster Name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: EKS Cluster Name is required.
    exit /b 1
)

set /p "IMAGE_URI=Enter Docker Image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest): "
if "!IMAGE_URI!"=="" (
    echo ERROR: Docker Image URI is required.
    exit /b 1
)

echo.
echo Configuration:
echo   AWS Region   : !AWS_REGION!
echo   EKS Cluster  : !CLUSTER_NAME!
echo   Image URI    : !IMAGE_URI!
echo   Namespace    : !NAMESPACE!
echo.

:: ── Configure kubectl for EKS ─────────────────────────────────────────────────
echo Configuring kubectl for EKS cluster '!CLUSTER_NAME!'...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to configure kubectl for EKS cluster.
    exit /b 1
)
echo kubectl configured successfully.
echo.

:: ── Verify cluster connectivity ───────────────────────────────────────────────
echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to EKS cluster.
    exit /b 1
)
echo.

:: ── Substitute placeholders in manifests ─────────────────────────────────────
echo Updating Kubernetes manifests with image URI...
powershell -NoProfile -Command "(Get-Content '!K8S_DIR!\deployment.yaml') -replace '{{IMAGE_URI}}', '!IMAGE_URI!' | Set-Content '!K8S_DIR!\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update deployment manifest.
    exit /b 1
)
echo Manifests updated.
echo.

:: ── Apply Kubernetes manifests ────────────────────────────────────────────────
echo Applying namespace...
kubectl apply -f !K8S_DIR!\namespace.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply namespace.
    exit /b 1
)

echo Applying deployment...
kubectl apply -f !K8S_DIR!\deployment.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply deployment.
    exit /b 1
)

echo Applying service...
kubectl apply -f !K8S_DIR!\service.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply service.
    exit /b 1
)

echo Applying ingress...
kubectl apply -f !K8S_DIR!\ingress.yaml
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply ingress.
    exit /b 1
)
echo.

:: ── Wait for rollout ──────────────────────────────────────────────────────────
echo Waiting for deployment rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo.
    echo ERROR: Deployment rollout timed out or failed.
    echo Run the following to investigate:
    echo   kubectl describe deployment/!APP_NAME! -n !NAMESPACE!
    echo   kubectl get pods -n !NAMESPACE!
    echo   kubectl logs -l app=!APP_NAME! -n !NAMESPACE! --tail=50
    echo.
    echo To rollback:
    echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    exit /b 1
)
echo.

:: ── Verify resources ──────────────────────────────────────────────────────────
echo Verifying deployed resources...
kubectl get pods,svc,ingress -n !NAMESPACE!
echo.

echo ==============================================
echo   Deployment successful!
echo   Run: kubectl get ingress -n !NAMESPACE!
echo   to retrieve the ALB hostname once provisioned.
echo ==============================================

endlocal
