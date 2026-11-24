@echo off
setlocal enabledelayedexpansion

set "APP_NAME=dashboard-app"
set "NAMESPACE=dashboard-app"

set /p AWS_REGION="AWS region (e.g. us-east-1): "
if "!AWS_REGION!"=="" (
  echo AWS region is required
  exit /b 1
)
set /p CLUSTER_NAME="EKS cluster name: "
if "!CLUSTER_NAME!"=="" (
  echo Cluster name is required
  exit /b 1
)
set /p IMAGE_URI="Docker image URI (registry/repo:tag): "
if "!IMAGE_URI!"=="" (
  echo Image URI is required
  exit /b 1
)
set /p SPRING_PROFILES_ACTIVE="Enter value for SPRING_PROFILES_ACTIVE (or press Enter for docker): "
if "!SPRING_PROFILES_ACTIVE!"=="" set "SPRING_PROFILES_ACTIVE=docker"

set "WORK_DIR=%TEMP%\!APP_NAME!-k8s-%RANDOM%"
mkdir "!WORK_DIR!"
copy /y kubernetes\*.yaml "!WORK_DIR!\" >nul

for %%F in ("!WORK_DIR!\*.yaml") do (
  powershell -NoProfile -Command "(Get-Content -Raw '%%~fF').Replace('{{IMAGE_URI}}','!IMAGE_URI!').Replace('{{SPRING_PROFILES_ACTIVE}}','!SPRING_PROFILES_ACTIVE!').Replace('{{NAMESPACE}}','!NAMESPACE!') | Set-Content -NoNewline '%%~fF'"
)

echo Configuring kubectl...
aws eks update-kubeconfig --region !AWS_REGION! --name !CLUSTER_NAME!
if !ERRORLEVEL! neq 0 (
  echo Failed to configure kubectl
  exit /b 1
)

echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
  echo Cannot reach cluster
  exit /b 1
)

echo Applying manifests...
kubectl apply -f "!WORK_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 exit /b 1
kubectl apply -f "!WORK_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 exit /b 1

echo Waiting for rollout...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
  echo Rollout failed. To roll back run:
  echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
  exit /b 1
)

kubectl get pods,svc,ingress -n !NAMESPACE!
echo Check the ingress ADDRESS above; health URL is http://ADDRESS/api/health

rmdir /s /q "!WORK_DIR!"
endlocal
