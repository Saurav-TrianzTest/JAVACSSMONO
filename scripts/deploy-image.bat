@echo off
setlocal enabledelayedexpansion

REM =============================================================================
REM deploy-image.bat — Deploy dashboard-app to AWS ECS Fargate
REM Platform: Windows
REM Usage: scripts\deploy-image.bat
REM Run from the repository root directory.
REM =============================================================================

set SERVICE_NAME=dashboard-app-service
set TASK_FAMILY=dashboard-app-task
set LOG_GROUP=/ecs/dashboard-app
set TASK_DEF_FILE=ecs\task-definition.json
set SERVICE_DEF_FILE=ecs\service-definition.json

echo ==============================================
echo   dashboard-app ^— ECS Fargate Deployment
echo ==============================================
echo.

REM ── AWS Region ────────────────────────────────────────────────────────────────
set /p AWS_REGION="AWS Region [us-east-1]: "
if "!AWS_REGION!"=="" set AWS_REGION=us-east-1

REM ── ECS Cluster ───────────────────────────────────────────────────────────────
set /p CLUSTER_NAME="ECS Cluster name [dashboard-app-cluster]: "
if "!CLUSTER_NAME!"=="" set CLUSTER_NAME=dashboard-app-cluster

REM ── Network configuration ─────────────────────────────────────────────────────
echo.
echo -- Network Configuration --------------------------------------------------
set /p VPC_ID="VPC ID (e.g. vpc-xxxxxxxx): "
set /p SUBNETS_RAW="Subnet IDs (comma-separated, e.g. subnet-aaa,subnet-bbb): "
set /p SECURITY_GROUP="Security Group ID (e.g. sg-xxxxxxxx): "

REM Parse subnets
for /f "tokens=1,2 delims=," %%a in ("!SUBNETS_RAW!") do (
    set SUBNET_1=%%a
    set SUBNET_2=%%b
)
REM Trim spaces
for /f "tokens=*" %%a in ("!SUBNET_1!") do set SUBNET_1=%%a
for /f "tokens=*" %%a in ("!SUBNET_2!") do set SUBNET_2=%%a
if "!SUBNET_2!"=="" set SUBNET_2=!SUBNET_1!

REM ── ECR Image URI ─────────────────────────────────────────────────────────────
echo.
set /p IMAGE_URI="ECR Image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest): "

REM ── AWS Account ID ────────────────────────────────────────────────────────────
echo.
echo Fetching AWS Account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set ACCOUNT_ID=%%i
echo Account ID    : !ACCOUNT_ID!

REM ── Ensure CloudWatch log group exists ────────────────────────────────────────
echo.
echo Ensuring CloudWatch log group '!LOG_GROUP!' exists...
aws logs create-log-group --log-group-name !LOG_GROUP! --region !AWS_REGION! >nul 2>&1
echo Log group ready.

REM ── Ensure ECS cluster exists ─────────────────────────────────────────────────
echo.
echo Checking ECS cluster '!CLUSTER_NAME!'...
for /f "delims=" %%i in ('aws ecs describe-clusters --clusters !CLUSTER_NAME! --region !AWS_REGION! --query "clusters[0].status" --output text 2^>nul') do set CLUSTER_STATUS=%%i
if "!CLUSTER_STATUS!" neq "ACTIVE" (
    echo Creating ECS cluster '!CLUSTER_NAME!'...
    aws ecs create-cluster --cluster-name !CLUSTER_NAME! --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS cluster.
        exit /b 1
    )
)
echo Cluster ready.

REM ── Load balancer prompt ──────────────────────────────────────────────────────
echo.
set /p NEED_LB="Do you need an Application Load Balancer for this service? (y/n) [n]: "
if "!NEED_LB!"=="" set NEED_LB=n

set TARGET_GROUP_ARN=
set ALB_DNS=

if /i "!NEED_LB!"=="y" (
    echo.
    echo -- Creating Application Load Balancer -------------------------------------
    set ALB_NAME=dashboard-app-alb

    echo Creating ALB '!ALB_NAME!'...
    for /f "delims=" %%i in ('aws elbv2 create-load-balancer --name !ALB_NAME! --subnets !SUBNET_1! !SUBNET_2! --security-groups !SECURITY_GROUP! --scheme internet-facing --type application --region !AWS_REGION! --query "LoadBalancers[0].LoadBalancerArn" --output text') do set ALB_ARN=%%i
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ALB.
        exit /b 1
    )
    echo ALB ARN       : !ALB_ARN!

    for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns !ALB_ARN! --region !AWS_REGION! --query "LoadBalancers[0].DNSName" --output text') do set ALB_DNS=%%i

    echo Creating Target Group 'dashboard-app-tg'...
    for /f "delims=" %%i in ('aws elbv2 create-target-group --name dashboard-app-tg --protocol HTTP --port 8080 --vpc-id !VPC_ID! --target-type ip --health-check-path "/api/health" --health-check-interval-seconds 30 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region !AWS_REGION! --query "TargetGroups[0].TargetGroupArn" --output text') do set TARGET_GROUP_ARN=%%i
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create Target Group.
        exit /b 1
    )
    echo Target Group  : !TARGET_GROUP_ARN!

    echo Creating ALB Listener on port 80...
    aws elbv2 create-listener --load-balancer-arn !ALB_ARN! --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=!TARGET_GROUP_ARN! --region !AWS_REGION! >nul
    echo ALB Listener created.
)

REM ── Prepare task definition with substituted placeholders ─────────────────────
echo.
echo Preparing task definition...
set TASK_DEF_TMP=%TEMP%\task-definition-tmp.json
copy /Y %TASK_DEF_FILE% %TASK_DEF_TMP% >nul

powershell -NoProfile -Command ^
  "(Get-Content '%TASK_DEF_TMP%') -replace '{{IMAGE_URI}}','!IMAGE_URI!' -replace '{{AWS_REGION}}','!AWS_REGION!' -replace '{{ACCOUNT_ID}}','!ACCOUNT_ID!' | Set-Content '%TASK_DEF_TMP%'"

REM ── Register task definition ──────────────────────────────────────────────────
echo Registering ECS task definition...
for /f "delims=" %%i in ('aws ecs register-task-definition --cli-input-json file://%TASK_DEF_TMP% --region !AWS_REGION! --query "taskDefinition.taskDefinitionArn" --output text') do set TASK_DEF_ARN=%%i
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to register task definition.
    del /f %TASK_DEF_TMP% >nul 2>&1
    exit /b 1
)
echo Task Def ARN  : !TASK_DEF_ARN!
del /f %TASK_DEF_TMP% >nul 2>&1

REM ── Prepare service definition ────────────────────────────────────────────────
echo.
echo Preparing service definition...
set SERVICE_DEF_TMP=%TEMP%\service-definition-tmp.json
copy /Y %SERVICE_DEF_FILE% %SERVICE_DEF_TMP% >nul

powershell -NoProfile -Command ^
  "(Get-Content '%SERVICE_DEF_TMP%') -replace '{{CLUSTER_NAME}}','!CLUSTER_NAME!' -replace '{{SUBNET_1}}','!SUBNET_1!' -replace '{{SUBNET_2}}','!SUBNET_2!' -replace '{{SECURITY_GROUP}}','!SECURITY_GROUP!' | Set-Content '%SERVICE_DEF_TMP%'"

REM ── Inject load balancer config if requested ──────────────────────────────────
if /i "!NEED_LB!"=="y" (
    if "!TARGET_GROUP_ARN!" neq "" (
        powershell -NoProfile -Command ^
          "$svc = Get-Content '%SERVICE_DEF_TMP%' | ConvertFrom-Json; $lb = @{targetGroupArn='!TARGET_GROUP_ARN!'; containerName='dashboard-app'; containerPort=8080}; $svc | Add-Member -NotePropertyName 'loadBalancers' -NotePropertyValue @($lb) -Force; $svc | Add-Member -NotePropertyName 'healthCheckGracePeriodSeconds' -NotePropertyValue 300 -Force; $svc | ConvertTo-Json -Depth 10 | Set-Content '%SERVICE_DEF_TMP%'"
    )
)

REM ── Create or update ECS service ──────────────────────────────────────────────
echo.
echo Checking if ECS service '!SERVICE_NAME!' exists...
for /f "delims=" %%i in ('aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[?status==`ACTIVE`].serviceName" --output text 2^>nul') do set EXISTING_SERVICE=%%i

if "!EXISTING_SERVICE!"=="" (
    echo Creating ECS service '!SERVICE_NAME!'...
    aws ecs create-service --cli-input-json file://%SERVICE_DEF_TMP% --region !AWS_REGION!
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS service.
        del /f %SERVICE_DEF_TMP% >nul 2>&1
        exit /b 1
    )
    echo Service created.
) else (
    echo Updating existing ECS service '!SERVICE_NAME!'...
    aws ecs update-service --cluster !CLUSTER_NAME! --service !SERVICE_NAME! --task-definition !TASK_DEF_ARN! --region !AWS_REGION! >nul
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to update ECS service.
        del /f %SERVICE_DEF_TMP% >nul 2>&1
        exit /b 1
    )
    echo Service updated.
)
del /f %SERVICE_DEF_TMP% >nul 2>&1

REM ── Wait for service stability ────────────────────────────────────────────────
echo.
echo Waiting for service to reach stable state (this may take a few minutes)...
aws ecs wait services-stable --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!
if !ERRORLEVEL! neq 0 (
    echo WARNING: Service did not reach stable state within the timeout period.
    echo Check the ECS console for task failure details.
)
echo Service is stable.

REM ── Verify deployment ─────────────────────────────────────────────────────────
echo.
echo -- Deployment Summary -----------------------------------------------------
aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION! --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}" --output table

echo.
echo CloudWatch Logs : !LOG_GROUP!
echo ECS Cluster     : !CLUSTER_NAME!
echo ECS Service     : !SERVICE_NAME!
echo Task Definition : !TASK_DEF_ARN!

if "!ALB_DNS!" neq "" (
    echo.
    echo Load Balancer DNS : http://!ALB_DNS!
    echo Health Check URL  : http://!ALB_DNS!/api/health
)

echo.
echo ==============================================
echo   Deployment complete!
echo ==============================================
echo.
echo Troubleshooting hints:
echo   - View task logs  : aws logs tail !LOG_GROUP! --follow --region !AWS_REGION!
echo   - List tasks      : aws ecs list-tasks --cluster !CLUSTER_NAME! --region !AWS_REGION!
echo   - Service events  : aws ecs describe-services --cluster !CLUSTER_NAME! --services !SERVICE_NAME! --region !AWS_REGION!

endlocal
