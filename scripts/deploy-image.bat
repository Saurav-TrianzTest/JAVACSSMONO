@echo off
setlocal enabledelayedexpansion

rem =============================================================================
rem deploy-image.bat — Deploy dashboard-app to AWS ECS Fargate (Windows)
rem Usage: scripts\deploy-image.bat  (run from repository root)
rem =============================================================================

set "PROJECT_NAME=dashboard-app"
set "SERVICE_NAME=dashboard-app-service"
set "TASK_FAMILY=dashboard-app-task"
set "LOG_GROUP=/ecs/dashboard-app"
set "TASK_DEF_FILE=ecs\task-definition.json"
set "SERVICE_DEF_FILE=ecs\service-definition.json"

echo ==============================================
echo   dashboard-app -- ECS Fargate Deployment
echo ==============================================
echo.

rem ------------------------------------------------------------------------------
rem Collect deployment parameters
rem ------------------------------------------------------------------------------
set /p "AWS_REGION=Enter AWS Region [us-east-1]: "
if "!AWS_REGION!"=="" set "AWS_REGION=us-east-1"

set /p "CLUSTER_NAME=Enter ECS Cluster name [dashboard-app-cluster]: "
if "!CLUSTER_NAME!"=="" set "CLUSTER_NAME=dashboard-app-cluster"

set /p "IMAGE_URI=Enter ECR Image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest): "
if "!IMAGE_URI!"=="" (
    echo ERROR: Image URI is required.
    exit /b 1
)

set /p "VPC_ID=Enter VPC ID (e.g. vpc-xxxxxxxx): "
if "!VPC_ID!"=="" (
    echo ERROR: VPC ID is required.
    exit /b 1
)

set /p "SUBNETS_INPUT=Enter Subnet IDs (comma-separated, e.g. subnet-aaa,subnet-bbb): "
if "!SUBNETS_INPUT!"=="" (
    echo ERROR: At least one subnet ID is required.
    exit /b 1
)

set /p "SECURITY_GROUP=Enter Security Group ID (e.g. sg-xxxxxxxx): "
if "!SECURITY_GROUP!"=="" (
    echo ERROR: Security Group ID is required.
    exit /b 1
)

rem Parse first two subnets
for /f "tokens=1,2 delims=," %%a in ("!SUBNETS_INPUT!") do (
    set "SUBNET_1=%%a"
    set "SUBNET_2=%%b"
)
if "!SUBNET_2!"=="" set "SUBNET_2=!SUBNET_1!"

rem Strip spaces from subnet values
set "SUBNET_1=!SUBNET_1: =!"
set "SUBNET_2=!SUBNET_2: =!"

rem ------------------------------------------------------------------------------
rem Retrieve AWS Account ID
rem ------------------------------------------------------------------------------
echo.
echo Retrieving AWS Account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set "ACCOUNT_ID=%%i"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to retrieve AWS Account ID. Check AWS CLI configuration.
    exit /b 1
)
echo AWS Account ID: !ACCOUNT_ID!

rem ------------------------------------------------------------------------------
rem Ensure CloudWatch log group exists
rem ------------------------------------------------------------------------------
echo.
echo Ensuring CloudWatch log group exists: !LOG_GROUP! ...
aws logs create-log-group --log-group-name "!LOG_GROUP!" --region "!AWS_REGION!" >nul 2>&1
echo Log group ready: !LOG_GROUP!

rem ------------------------------------------------------------------------------
rem Ensure ECS cluster exists
rem ------------------------------------------------------------------------------
echo.
echo Checking ECS cluster: !CLUSTER_NAME! ...
for /f "delims=" %%i in ('aws ecs describe-clusters --clusters "!CLUSTER_NAME!" --region "!AWS_REGION!" --query "clusters[0].status" --output text 2^>nul') do set "CLUSTER_STATUS=%%i"

if not "!CLUSTER_STATUS!"=="ACTIVE" (
    echo Creating ECS cluster: !CLUSTER_NAME! ...
    aws ecs create-cluster --cluster-name "!CLUSTER_NAME!" --region "!AWS_REGION!"
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS cluster.
        exit /b 1
    )
    echo ECS cluster created: !CLUSTER_NAME!
) else (
    echo ECS cluster already exists: !CLUSTER_NAME!
)

rem ------------------------------------------------------------------------------
rem Load balancer (optional)
rem ------------------------------------------------------------------------------
echo.
set /p "NEED_LB=Do you need an Application Load Balancer for this service? (y/n) [n]: "
if "!NEED_LB!"=="" set "NEED_LB=n"

set "TARGET_GROUP_ARN="
set "LB_DNS="

if /i "!NEED_LB!"=="y" (
    echo.
    echo Creating Application Load Balancer...

    set "LB_NAME=!PROJECT_NAME!-alb"
    set "TG_NAME=!PROJECT_NAME!-tg"

    rem Build subnet list (space-separated for CLI)
    set "SUBNET_LIST=!SUBNETS_INPUT:,= !"

    for /f "delims=" %%i in ('aws elbv2 create-load-balancer --name "!LB_NAME!" --subnets !SUBNET_LIST! --security-groups "!SECURITY_GROUP!" --scheme internet-facing --type application --region "!AWS_REGION!" --query "LoadBalancers[0].LoadBalancerArn" --output text') do set "LB_ARN=%%i"
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ALB.
        exit /b 1
    )
    echo ALB created: !LB_ARN!

    for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns "!LB_ARN!" --region "!AWS_REGION!" --query "LoadBalancers[0].DNSName" --output text') do set "LB_DNS=%%i"

    for /f "delims=" %%i in ('aws elbv2 create-target-group --name "!TG_NAME!" --protocol HTTP --port 8080 --vpc-id "!VPC_ID!" --target-type ip --health-check-path "/api/health" --health-check-interval-seconds 30 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region "!AWS_REGION!" --query "TargetGroups[0].TargetGroupArn" --output text') do set "TARGET_GROUP_ARN=%%i"
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create Target Group.
        exit /b 1
    )
    echo Target Group created: !TARGET_GROUP_ARN!

    aws elbv2 create-listener --load-balancer-arn "!LB_ARN!" --protocol HTTP --port 80 --default-actions "Type=forward,TargetGroupArn=!TARGET_GROUP_ARN!" --region "!AWS_REGION!" >nul
    echo ALB listener created.
)

rem ------------------------------------------------------------------------------
rem Prepare working copies of task/service definition files
rem ------------------------------------------------------------------------------
set "WORK_DIR=%TEMP%\ecs-deploy-%RANDOM%"
mkdir "!WORK_DIR!"
copy "!TASK_DEF_FILE!" "!WORK_DIR!\task-definition.json" >nul
copy "!SERVICE_DEF_FILE!" "!WORK_DIR!\service-definition.json" >nul

rem Replace placeholders using PowerShell
powershell -NoProfile -Command ^
    "(Get-Content '!WORK_DIR!\task-definition.json') -replace '{{IMAGE_URI}}','!IMAGE_URI!' -replace '{{AWS_REGION}}','!AWS_REGION!' -replace '{{ACCOUNT_ID}}','!ACCOUNT_ID!' | Set-Content '!WORK_DIR!\task-definition.json'"

powershell -NoProfile -Command ^
    "(Get-Content '!WORK_DIR!\service-definition.json') -replace '{{CLUSTER_NAME}}','!CLUSTER_NAME!' -replace '{{SUBNET_1}}','!SUBNET_1!' -replace '{{SUBNET_2}}','!SUBNET_2!' -replace '{{SECURITY_GROUP}}','!SECURITY_GROUP!' | Set-Content '!WORK_DIR!\service-definition.json'"

rem Inject loadBalancers block if ALB was created
if not "!TARGET_GROUP_ARN!"=="" (
    powershell -NoProfile -Command ^
        "$svc = Get-Content '!WORK_DIR!\service-definition.json' | ConvertFrom-Json; $svc | Add-Member -MemberType NoteProperty -Name 'loadBalancers' -Value @(@{targetGroupArn='!TARGET_GROUP_ARN!';containerName='dashboard-app';containerPort=8080}) -Force; $svc | Add-Member -MemberType NoteProperty -Name 'healthCheckGracePeriodSeconds' -Value 300 -Force; $svc | ConvertTo-Json -Depth 10 | Set-Content '!WORK_DIR!\service-definition.json'"
    echo loadBalancers section injected.
)

rem ------------------------------------------------------------------------------
rem Register task definition
rem ------------------------------------------------------------------------------
echo.
echo Registering ECS task definition: !TASK_FAMILY! ...
for /f "delims=" %%i in ('aws ecs register-task-definition --cli-input-json "file://!WORK_DIR!\task-definition.json" --region "!AWS_REGION!" --query "taskDefinition.taskDefinitionArn" --output text') do set "TASK_DEF_ARN=%%i"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to register task definition.
    exit /b 1
)
echo Task definition registered: !TASK_DEF_ARN!

rem Update service definition with full task ARN
powershell -NoProfile -Command ^
    "(Get-Content '!WORK_DIR!\service-definition.json') -replace '\"taskDefinition\": \"!TASK_FAMILY!\"','\"taskDefinition\": \"!TASK_DEF_ARN!\"' | Set-Content '!WORK_DIR!\service-definition.json'"

rem ------------------------------------------------------------------------------
rem Create or update ECS service
rem ------------------------------------------------------------------------------
echo.
echo Checking if ECS service exists: !SERVICE_NAME! ...
for /f "delims=" %%i in ('aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!" --query "services[?status!=`INACTIVE`].serviceName" --output text 2^>nul') do set "EXISTING_SERVICE=%%i"

if "!EXISTING_SERVICE!"=="" (
    echo Creating ECS service: !SERVICE_NAME! ...
    aws ecs create-service --cli-input-json "file://!WORK_DIR!\service-definition.json" --region "!AWS_REGION!"
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to create ECS service.
        exit /b 1
    )
    echo ECS service created: !SERVICE_NAME!
) else (
    echo Updating existing ECS service: !SERVICE_NAME! ...
    aws ecs update-service --cluster "!CLUSTER_NAME!" --service "!SERVICE_NAME!" --task-definition "!TASK_DEF_ARN!" --region "!AWS_REGION!" >nul
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Failed to update ECS service.
        exit /b 1
    )
    echo ECS service updated: !SERVICE_NAME!
)

rem ------------------------------------------------------------------------------
rem Wait for service stability
rem ------------------------------------------------------------------------------
echo.
echo Waiting for service to become stable (this may take a few minutes)...
aws ecs wait services-stable --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!"
if !ERRORLEVEL! neq 0 (
    echo WARNING: Service did not stabilize within the expected time. Check ECS console.
) else (
    echo Service is stable.
)

rem ------------------------------------------------------------------------------
rem Verify deployment
rem ------------------------------------------------------------------------------
echo.
echo Verifying deployment...
aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!" --query "services[0].{ServiceName:serviceName,Status:status,DesiredCount:desiredCount,RunningCount:runningCount,PendingCount:pendingCount}"

rem ------------------------------------------------------------------------------
rem Summary
rem ------------------------------------------------------------------------------
echo.
echo ==============================================
echo   Deployment Complete!
echo   Cluster      : !CLUSTER_NAME!
echo   Service      : !SERVICE_NAME!
echo   Task Def ARN : !TASK_DEF_ARN!
echo   Image        : !IMAGE_URI!
echo   Log Group    : !LOG_GROUP!
if not "!LB_DNS!"=="" echo   ALB DNS      : http://!LB_DNS!
echo ==============================================
echo.
echo Troubleshooting tips:
echo   - View logs  : aws logs tail !LOG_GROUP! --follow --region !AWS_REGION!
echo   - List tasks : aws ecs list-tasks --cluster !CLUSTER_NAME! --service-name !SERVICE_NAME! --region !AWS_REGION!

rem Cleanup temp files
rmdir /s /q "!WORK_DIR!" >nul 2>&1

endlocal
exit /b 0
