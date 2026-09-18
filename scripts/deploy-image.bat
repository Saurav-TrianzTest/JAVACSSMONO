@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: deploy-image.bat — Deploy dashboard-app to AWS ECS Fargate (Windows)
:: Application: dashboard-app (Spring Boot 3.2.5 / Java 17)
:: =============================================================================

set "PROJECT_NAME=dashboard-app"
set "TASK_FAMILY=dashboard-app-task"
set "SERVICE_NAME=dashboard-app-service"
set "LOG_GROUP=/ecs/dashboard-app"
set "TASK_DEF_FILE=ecs\task-definition.json"
set "SERVICE_DEF_FILE=ecs\service-definition.json"

echo.
echo ============================================================
echo   dashboard-app -- AWS ECS Fargate Deployment (Windows)
echo   Spring Boot 3.2.5 / Java 17
echo ============================================================
echo.

:: -----------------------------------------------------------------------------
:: Prerequisite checks
:: -----------------------------------------------------------------------------
echo [INFO]  Checking prerequisites...
where aws >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] aws CLI not found. Install from https://aws.amazon.com/cli/
    exit /b 1
)
echo [OK]    Prerequisites OK.

:: -----------------------------------------------------------------------------
:: Gather deployment parameters
:: -----------------------------------------------------------------------------
echo.
echo [INFO]  === Deployment Configuration ===
set /p "AWS_REGION=AWS Region (e.g. us-east-1)                          : "
set /p "CLUSTER_INPUT=ECS Cluster name [default: dashboard-app-cluster]  : "
if "!CLUSTER_INPUT!"=="" (
    set "CLUSTER_NAME=dashboard-app-cluster"
) else (
    set "CLUSTER_NAME=!CLUSTER_INPUT!"
)
set /p "IMAGE_URI=ECR Image URI (e.g. 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest): "
set /p "VPC_ID=VPC ID (e.g. vpc-xxxxxxxx)                           : "
set /p "SUBNETS_RAW=Subnet IDs (comma-separated, e.g. subnet-aaa,subnet-bbb): "
set /p "SECURITY_GROUP=Security Group ID (e.g. sg-xxxxxxxx)                 : "

:: Parse subnets
for /f "tokens=1,2 delims=," %%a in ("!SUBNETS_RAW!") do (
    set "SUBNET_1=%%a"
    set "SUBNET_2=%%b"
)
if "!SUBNET_2!"=="" set "SUBNET_2=!SUBNET_1!"

echo.
echo [INFO]  Region        : !AWS_REGION!
echo [INFO]  Cluster       : !CLUSTER_NAME!
echo [INFO]  Image URI     : !IMAGE_URI!
echo [INFO]  VPC           : !VPC_ID!
echo [INFO]  Subnet 1      : !SUBNET_1!
echo [INFO]  Subnet 2      : !SUBNET_2!
echo [INFO]  Security Group: !SECURITY_GROUP!

:: -----------------------------------------------------------------------------
:: Retrieve AWS Account ID
:: -----------------------------------------------------------------------------
echo.
echo [INFO]  Retrieving AWS Account ID...
for /f "delims=" %%i in ('aws sts get-caller-identity --query Account --output text') do set "ACCOUNT_ID=%%i"
if !ERRORLEVEL! neq 0 (
    echo [ERROR] Failed to retrieve AWS Account ID. Check your AWS credentials.
    exit /b 1
)
echo [OK]    Account ID    : !ACCOUNT_ID!

:: -----------------------------------------------------------------------------
:: Ensure CloudWatch log group exists
:: -----------------------------------------------------------------------------
echo.
echo [INFO]  Ensuring CloudWatch log group '!LOG_GROUP!' exists...
aws logs create-log-group --log-group-name "!LOG_GROUP!" --region "!AWS_REGION!" >nul 2>&1
echo [OK]    CloudWatch log group ready: !LOG_GROUP!

:: -----------------------------------------------------------------------------
:: Ensure ECS cluster exists
:: -----------------------------------------------------------------------------
echo.
echo [INFO]  Checking ECS cluster '!CLUSTER_NAME!'...
for /f "delims=" %%i in ('aws ecs describe-clusters --clusters "!CLUSTER_NAME!" --region "!AWS_REGION!" --query "clusters[0].status" --output text 2^>nul') do set "CLUSTER_STATUS=%%i"
if "!CLUSTER_STATUS!" neq "ACTIVE" (
    echo [INFO]  Cluster not found -- creating '!CLUSTER_NAME!'...
    aws ecs create-cluster --cluster-name "!CLUSTER_NAME!" --region "!AWS_REGION!" --capacity-providers FARGATE FARGATE_SPOT >nul
    if !ERRORLEVEL! neq 0 (
        echo [ERROR] Failed to create ECS cluster.
        exit /b 1
    )
    echo [OK]    ECS cluster '!CLUSTER_NAME!' created.
) else (
    echo [OK]    ECS cluster '!CLUSTER_NAME!' is ACTIVE.
)

:: -----------------------------------------------------------------------------
:: Load Balancer (optional)
:: -----------------------------------------------------------------------------
echo.
set /p "NEED_LB=Do you need an Application Load Balancer for this service? (y/n) [default: n]: "
if "!NEED_LB!"=="" set "NEED_LB=n"
set "TARGET_GROUP_ARN="
set "ALB_DNS="

if /i "!NEED_LB!"=="y" (
    echo [INFO]  Creating Application Load Balancer...
    set "ALB_NAME=dashboard-app-alb"

    for /f "delims=" %%i in ('aws elbv2 create-load-balancer --name "!ALB_NAME!" --subnets "!SUBNET_1!" "!SUBNET_2!" --security-groups "!SECURITY_GROUP!" --scheme internet-facing --type application --ip-address-type ipv4 --region "!AWS_REGION!" --query "LoadBalancers[0].LoadBalancerArn" --output text') do set "ALB_ARN=%%i"
    if !ERRORLEVEL! neq 0 (
        echo [ERROR] Failed to create ALB.
        exit /b 1
    )
    echo [OK]    ALB created: !ALB_ARN!

    for /f "delims=" %%i in ('aws elbv2 describe-load-balancers --load-balancer-arns "!ALB_ARN!" --region "!AWS_REGION!" --query "LoadBalancers[0].DNSName" --output text') do set "ALB_DNS=%%i"

    set "TG_NAME=dashboard-app-tg"
    echo [INFO]  Creating Target Group '!TG_NAME!' (target-type: ip)...
    for /f "delims=" %%i in ('aws elbv2 create-target-group --name "!TG_NAME!" --protocol HTTP --port 8080 --vpc-id "!VPC_ID!" --target-type ip --health-check-protocol HTTP --health-check-path "/api/health" --health-check-interval-seconds 30 --health-check-timeout-seconds 10 --healthy-threshold-count 2 --unhealthy-threshold-count 3 --region "!AWS_REGION!" --query "TargetGroups[0].TargetGroupArn" --output text') do set "TARGET_GROUP_ARN=%%i"
    if !ERRORLEVEL! neq 0 (
        echo [ERROR] Failed to create Target Group.
        exit /b 1
    )
    echo [OK]    Target Group created: !TARGET_GROUP_ARN!

    echo [INFO]  Creating ALB Listener on port 80...
    aws elbv2 create-listener --load-balancer-arn "!ALB_ARN!" --protocol HTTP --port 80 --default-actions "Type=forward,TargetGroupArn=!TARGET_GROUP_ARN!" --region "!AWS_REGION!" >nul
    echo [OK]    ALB Listener created.
)

:: -----------------------------------------------------------------------------
:: Prepare task definition — replace placeholders using PowerShell
:: -----------------------------------------------------------------------------
echo.
echo [INFO]  Preparing task definition...
set "TASK_DEF_TMP=%TEMP%\task-definition-deploy.json"
copy /y "!TASK_DEF_FILE!" "!TASK_DEF_TMP!" >nul

powershell -NoProfile -Command ^
  "(Get-Content '!TASK_DEF_TMP!') -replace '{{IMAGE_URI}}','!IMAGE_URI!' -replace '{{AWS_REGION}}','!AWS_REGION!' -replace '{{ACCOUNT_ID}}','!ACCOUNT_ID!' | Set-Content '!TASK_DEF_TMP!'"
echo [OK]    Task definition prepared.

:: -----------------------------------------------------------------------------
:: Register task definition
:: -----------------------------------------------------------------------------
echo [INFO]  Registering ECS task definition '!TASK_FAMILY!'...
for /f "delims=" %%i in ('aws ecs register-task-definition --cli-input-json "file://!TASK_DEF_TMP!" --region "!AWS_REGION!" --query "taskDefinition.taskDefinitionArn" --output text') do set "TASK_DEF_ARN=%%i"
if !ERRORLEVEL! neq 0 (
    echo [ERROR] Failed to register task definition.
    exit /b 1
)
echo [OK]    Task definition registered: !TASK_DEF_ARN!

:: -----------------------------------------------------------------------------
:: Prepare service definition — replace placeholders
:: -----------------------------------------------------------------------------
echo [INFO]  Preparing service definition...
set "SERVICE_DEF_TMP=%TEMP%\service-definition-deploy.json"
copy /y "!SERVICE_DEF_FILE!" "!SERVICE_DEF_TMP!" >nul

powershell -NoProfile -Command ^
  "(Get-Content '!SERVICE_DEF_TMP!') -replace '{{CLUSTER_NAME}}','!CLUSTER_NAME!' -replace '{{SUBNET_1}}','!SUBNET_1!' -replace '{{SUBNET_2}}','!SUBNET_2!' -replace '{{SECURITY_GROUP}}','!SECURITY_GROUP!' | Set-Content '!SERVICE_DEF_TMP!'"

if "!TARGET_GROUP_ARN!" neq "" (
    echo [INFO]  Injecting load balancer configuration...
    powershell -NoProfile -Command ^
      "$svc = Get-Content '!SERVICE_DEF_TMP!' | ConvertFrom-Json; $lb = @{targetGroupArn='!TARGET_GROUP_ARN!'; containerName='dashboard-app'; containerPort=8080}; $svc | Add-Member -NotePropertyName 'loadBalancers' -NotePropertyValue @($lb) -Force; $svc | Add-Member -NotePropertyName 'healthCheckGracePeriodSeconds' -NotePropertyValue 300 -Force; $svc | ConvertTo-Json -Depth 10 | Set-Content '!SERVICE_DEF_TMP!'"
    echo [OK]    Load balancer configuration injected.
)
echo [OK]    Service definition prepared.

:: -----------------------------------------------------------------------------
:: Create or update ECS service
:: -----------------------------------------------------------------------------
echo.
echo [INFO]  Checking if ECS service '!SERVICE_NAME!' exists...
for /f "delims=" %%i in ('aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!" --query "services[?status!='INACTIVE'].serviceName" --output text 2^>nul') do set "EXISTING_SERVICE=%%i"

if "!EXISTING_SERVICE!"=="" (
    echo [INFO]  Service does not exist -- creating '!SERVICE_NAME!'...
    aws ecs create-service --cli-input-json "file://!SERVICE_DEF_TMP!" --region "!AWS_REGION!" >nul
    if !ERRORLEVEL! neq 0 (
        echo [ERROR] Failed to create ECS service.
        exit /b 1
    )
    echo [OK]    ECS service '!SERVICE_NAME!' created.
) else (
    echo [INFO]  Service exists -- updating '!SERVICE_NAME!'...
    aws ecs update-service --cluster "!CLUSTER_NAME!" --service "!SERVICE_NAME!" --task-definition "!TASK_DEF_ARN!" --region "!AWS_REGION!" >nul
    if !ERRORLEVEL! neq 0 (
        echo [ERROR] Failed to update ECS service.
        exit /b 1
    )
    echo [OK]    ECS service '!SERVICE_NAME!' updated.
)

:: -----------------------------------------------------------------------------
:: Wait for service stability
:: -----------------------------------------------------------------------------
echo.
echo [INFO]  Waiting for service to reach stable state (this may take a few minutes)...
aws ecs wait services-stable --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!"
if !ERRORLEVEL! neq 0 (
    echo [WARN]  Service stability wait timed out. Check ECS console for details.
) else (
    echo [OK]    Service is stable.
)

:: -----------------------------------------------------------------------------
:: Verify deployment
:: -----------------------------------------------------------------------------
echo.
echo [INFO]  Verifying deployment...
aws ecs describe-services --cluster "!CLUSTER_NAME!" --services "!SERVICE_NAME!" --region "!AWS_REGION!" --query "services[0].{Status:status,Running:runningCount,Desired:desiredCount,Pending:pendingCount}" --output table

:: -----------------------------------------------------------------------------
:: Summary
:: -----------------------------------------------------------------------------
echo.
echo ============================================================
echo [OK]    Deployment complete!
echo.
echo   Cluster       : !CLUSTER_NAME!
echo   Service       : !SERVICE_NAME!
echo   Task Def ARN  : !TASK_DEF_ARN!
echo   CloudWatch    : !LOG_GROUP!
if "!ALB_DNS!" neq "" (
    echo   Load Balancer : http://!ALB_DNS!
    echo   Health Check  : http://!ALB_DNS!/api/health
)
echo ============================================================
echo.
echo [INFO]  Troubleshooting:
echo [INFO]    View logs  : aws logs tail !LOG_GROUP! --follow --region !AWS_REGION!
echo [INFO]    List tasks : aws ecs list-tasks --cluster !CLUSTER_NAME! --service-name !SERVICE_NAME! --region !AWS_REGION!
echo.

endlocal
