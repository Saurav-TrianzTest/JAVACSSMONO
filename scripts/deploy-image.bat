@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM deploy-image.bat - Deploy dashboard-app to AWS EKS (Windows)
REM Usage: scripts\deploy-image.bat  (run from repository root)
REM =============================================================================

set "APP_NAME=dashboard-app"
set "NAMESPACE=dashboard-app"
set "K8S_DIR=kubernetes"

echo ==============================================
echo   dashboard-app - AWS EKS Deployment
echo ==============================================
echo.

REM ---------------------------------------------------------------------------
REM Collect deployment parameters
REM ---------------------------------------------------------------------------
set /p "AWS_REGION=Enter AWS Region (e.g. us-east-1): "
if "!AWS_REGION!"=="" (
    echo ERROR: AWS Region is required.
    exit /b 1
)

set /p "CLUSTER_NAME=Enter EKS Cluster Name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: EKS Cluster Name is required.
    exit /b 1
)

set /p "IMAGE_URI=Enter full Docker image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest): "
if "!IMAGE_URI!"=="" (
    echo ERROR: Docker image URI is required.
    exit /b 1
)

echo.

REM ---------------------------------------------------------------------------
REM Configure kubectl for EKS
REM ---------------------------------------------------------------------------
echo Configuring kubectl for EKS cluster: !CLUSTER_NAME! in !AWS_REGION! ...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to configure kubectl for EKS.
    exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to EKS cluster.
    exit /b 1
)
echo.

REM ---------------------------------------------------------------------------
REM Substitute {{IMAGE_URI}} placeholder in deployment manifest
REM ---------------------------------------------------------------------------
echo Updating Kubernetes manifests with image URI...
copy "!K8S_DIR!\deployment.yaml" "!K8S_DIR!\deployment.yaml.bak" >nul

REM Use PowerShell to perform the sed-equivalent substitution on Windows
powershell -Command "(Get-Content '!K8S_DIR!\deployment.yaml') -replace '\{\{IMAGE_URI\}\}', '!IMAGE_URI!' | Set-Content '!K8S_DIR!\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update deployment manifest.
    copy "!K8S_DIR!\deployment.yaml.bak" "!K8S_DIR!\deployment.yaml" >nul
    exit /b 1
)

REM ---------------------------------------------------------------------------
REM Apply manifests in dependency order
REM ---------------------------------------------------------------------------
echo.
echo Applying Kubernetes manifests...

echo   [1/4] Applying namespace...
kubectl apply -f "!K8S_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply namespace manifest.
    copy "!K8S_DIR!\deployment.yaml.bak" "!K8S_DIR!\deployment.yaml" >nul
    exit /b 1
)

echo   [2/4] Applying deployment...
kubectl apply -f "!K8S_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply deployment manifest.
    copy "!K8S_DIR!\deployment.yaml.bak" "!K8S_DIR!\deployment.yaml" >nul
    exit /b 1
)

echo   [3/4] Applying service...
kubectl apply -f "!K8S_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply service manifest.
    copy "!K8S_DIR!\deployment.yaml.bak" "!K8S_DIR!\deployment.yaml" >nul
    exit /b 1
)

echo   [4/4] Applying ingress...
kubectl apply -f "!K8S_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply ingress manifest.
    copy "!K8S_DIR!\deployment.yaml.bak" "!K8S_DIR!\deployment.yaml" >nul
    exit /b 1
)

REM ---------------------------------------------------------------------------
REM Restore original deployment manifest (with placeholder)
REM ---------------------------------------------------------------------------
copy "!K8S_DIR!\deployment.yaml.bak" "!K8S_DIR!\deployment.yaml" >nul
del "!K8S_DIR!\deployment.yaml.bak" >nul 2>&1

REM ---------------------------------------------------------------------------
REM Wait for rollout to complete
REM ---------------------------------------------------------------------------
echo.
echo Waiting for deployment rollout to complete...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo ERROR: Deployment rollout did not complete successfully.
    echo Rollback command: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    exit /b 1
)

REM ---------------------------------------------------------------------------
REM Verify deployed resources
REM ---------------------------------------------------------------------------
echo.
echo Deployed resources in namespace '!NAMESPACE!':
kubectl get pods,svc,ingress -n !NAMESPACE!

REM ---------------------------------------------------------------------------
REM Display application URL
REM ---------------------------------------------------------------------------
echo.
echo Fetching application ingress URL...
for /f "tokens=*" %%i in ('kubectl get ingress !APP_NAME!-ingress -n !NAMESPACE! -o jsonpath^="{.status.loadBalancer.ingress[0].hostname}" 2^>nul') do (
    set "INGRESS_HOST=%%i"
)
if defined INGRESS_HOST (
    echo Application is accessible at: http://!INGRESS_HOST!
) else (
    echo Ingress hostname not yet assigned. Run the following to check:
    echo   kubectl get ingress -n !NAMESPACE!
)

echo.
echo ==============================================
echo   Deployment Complete!
echo   App     : !APP_NAME!
echo   Image   : !IMAGE_URI!
echo   Cluster : !CLUSTER_NAME!
echo   Region  : !AWS_REGION!
echo ==============================================
echo.
echo Rollback command (if needed):
echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

endlocal
