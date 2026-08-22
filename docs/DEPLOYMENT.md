# Deployment Guide — dashboard-app on AWS ECS Fargate

## Overview

This guide covers building, pushing, and deploying the **dashboard-app** Spring Boot application to **AWS ECS Fargate** using the generated containerization artifacts.

| Property | Value |
|---|---|
| Application | dashboard-app |
| Framework | Spring Boot 3.2.5 |
| Java Version | 17 |
| Build Tool | Maven |
| Package Type | JAR |
| Application Port | 8080 |
| Health Endpoint | `/api/health` |
| Target Platform | AWS ECS Fargate |

---

## Prerequisites

### Local Development Tools
- **Docker** 20.10+ — [Install Docker](https://docs.docker.com/get-docker/)
- **Java 17** (JDK) — [Eclipse Temurin](https://adoptium.net/)
- **Maven 3.9+** — [Install Maven](https://maven.apache.org/install.html)

### AWS Deployment Tools
- **AWS CLI v2** — [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
- **AWS Account** with appropriate IAM permissions
- **Docker** (for building and pushing images)

### AWS Infrastructure Required
- **VPC** with at least 2 subnets (preferably in different Availability Zones)
- **Security Group** allowing inbound TCP on port 8080 (and port 80 if using ALB)
- **IAM Roles** (see IAM Setup section below)
- **ECR Repository** (auto-created by `build-push.sh`)
- **CloudWatch Log Group** `/ecs/dashboard-app` (auto-created by `deploy-image.sh`)

---

## Project Structure

```
JAVACSSMONOGIT/
├── Dockerfile                    # Multi-stage build (Maven builder + JRE runtime)
├── docker-compose.yml            # Local development with Docker Compose
├── .dockerignore                 # Excludes build artefacts and wrapper files
├── pom.xml                       # Maven build descriptor
├── src/
│   └── main/
│       ├── java/com/trianz/dashboard/
│       │   ├── DashboardApplication.java
│       │   ├── controller/HealthController.java
│       │   └── service/HealthService.java
│       └── resources/
│           └── application.properties
├── ecs/
│   ├── task-definition.json      # ECS Fargate task definition
│   └── service-definition.json  # ECS Fargate service definition
├── scripts/
│   ├── build-push.sh             # Linux/macOS: build & push to ECR or Docker Hub
│   ├── build-push.bat            # Windows: build & push to ECR or Docker Hub
│   ├── deploy-image.sh           # Linux/macOS: deploy to ECS Fargate
│   └── deploy-image.bat          # Windows: deploy to ECS Fargate
└── docs/
    └── DEPLOYMENT.md             # This file
```

---

## IAM Setup

### ECS Task Execution Role
The execution role allows ECS to pull images from ECR and write logs to CloudWatch.

```bash
# Create the execution role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# Attach the managed policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

### ECS Task Role (Optional)
The task role grants permissions to the running application container (e.g., S3, DynamoDB access).

```bash
aws iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ecs-tasks.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'
```

---

## Local Development Setup

### 1. Build and Run with Maven

```bash
# Build the application
mvn clean package -DskipTests

# Run locally
java -jar target/dashboard-app-1.0.0.jar
```

Application will be available at: `http://localhost:8080`  
Health check: `http://localhost:8080/api/health`

### 2. Build and Run with Docker Compose

```bash
# Build and start the application container
docker compose up --build

# Run in detached mode
docker compose up --build -d

# View logs
docker compose logs -f dashboard-app

# Stop the application
docker compose down
```

### 3. Build Docker Image Manually

```bash
# Build the image
docker build -t dashboard-app:latest .

# Run the container
docker run -p 8080:8080 \
  -e SPRING_PROFILES_ACTIVE=docker \
  -e JAVA_OPTS="-Xms256m -Xmx512m" \
  dashboard-app:latest
```

---

## Build and Push to Registry

### Linux / macOS

```bash
# Make the script executable
chmod +x scripts/build-push.sh

# Run the build and push script
./scripts/build-push.sh
```

### Windows

```cmd
scripts\build-push.bat
```

The script will prompt you to:
1. Select registry type (AWS ECR or Docker Hub)
2. Enter registry credentials and details
3. Enter an image tag (defaults to `latest`)

The script automatically:
- Sanitises the image name (lowercase, hyphens)
- Creates the ECR repository if it does not exist (ECR only)
- Builds the Docker image
- Pushes to the selected registry

---

## AWS ECS Fargate Deployment

### ECS Fargate Architecture

```
Internet
    │
    ▼
[Application Load Balancer] (optional)
    │  port 80 → port 8080
    ▼
[ECS Fargate Service]
    │
    ├── Task 1: dashboard-app container (port 8080)
    └── Task 2: dashboard-app container (port 8080)
         │
         └── CloudWatch Logs: /ecs/dashboard-app
```

### ECS Task Definition Explained

The task definition (`ecs/task-definition.json`) configures:

| Field | Value | Notes |
|---|---|---|
| `family` | `dashboard-app-task` | Task definition family name |
| `requiresCompatibilities` | `["FARGATE"]` | Fargate launch type |
| `networkMode` | `awsvpc` | Required for Fargate |
| `cpu` | `512` | 0.5 vCPU |
| `memory` | `1024` | 1 GB RAM |
| `executionRoleArn` | `ecsTaskExecutionRole` | ECR pull + CloudWatch logs |
| `containerPort` | `8080` | Spring Boot application port |

**Valid Fargate CPU/Memory Combinations:**

| CPU | Memory Options |
|---|---|
| 256 (.25 vCPU) | 512, 1024, 2048 MB |
| **512 (.5 vCPU)** | **1024**, 2048, 3072, 4096 MB |
| 1024 (1 vCPU) | 2048–8192 MB |
| 2048 (2 vCPU) | 4096–16384 MB |
| 4096 (4 vCPU) | 8192–30720 MB |

### ECS Service Configuration

The service definition (`ecs/service-definition.json`) configures:

| Field | Value | Notes |
|---|---|---|
| `launchType` | `FARGATE` | Serverless compute |
| `desiredCount` | `2` | Two running tasks for HA |
| `assignPublicIp` | `ENABLED` | Required for public ECR access |
| `maximumPercent` | `200` | Rolling deployment |
| `minimumHealthyPercent` | `50` | Minimum healthy tasks during deploy |

### Deploy to ECS Fargate

#### Linux / macOS

```bash
# Make the script executable
chmod +x scripts/deploy-image.sh

# Run the deployment script
./scripts/deploy-image.sh
```

#### Windows

```cmd
scripts\deploy-image.bat
```

The deployment script will prompt for:
- AWS Region
- ECS Cluster name
- VPC ID
- Subnet IDs (comma-separated, at least 2)
- Security Group ID
- ECR Image URI

The script automatically:
1. Fetches your AWS Account ID
2. Creates the CloudWatch log group `/ecs/dashboard-app`
3. Creates the ECS cluster if it does not exist
4. Optionally creates an Application Load Balancer and Target Group
5. Registers the ECS task definition
6. Creates or updates the ECS service
7. Waits for the service to reach a stable state
8. Displays deployment summary

### Step-by-Step Manual Deployment

If you prefer to deploy manually:

```bash
# 1. Set variables
export AWS_REGION="us-east-1"
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CLUSTER_NAME="dashboard-app-cluster"
export IMAGE_URI="<your-ecr-uri>/dashboard-app:latest"

# 2. Create CloudWatch log group
aws logs create-log-group --log-group-name /ecs/dashboard-app --region $AWS_REGION

# 3. Create ECS cluster
aws ecs create-cluster --cluster-name $CLUSTER_NAME --region $AWS_REGION

# 4. Substitute placeholders in task definition
sed -e "s|{{IMAGE_URI}}|$IMAGE_URI|g" \
    -e "s|{{AWS_REGION}}|$AWS_REGION|g" \
    -e "s|{{ACCOUNT_ID}}|$ACCOUNT_ID|g" \
    ecs/task-definition.json > /tmp/task-def.json

# 5. Register task definition
TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file:///tmp/task-def.json \
  --region $AWS_REGION \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

# 6. Substitute placeholders in service definition
sed -e "s|{{CLUSTER_NAME}}|$CLUSTER_NAME|g" \
    -e "s|{{SUBNET_1}}|subnet-xxxxxxxx|g" \
    -e "s|{{SUBNET_2}}|subnet-yyyyyyyy|g" \
    -e "s|{{SECURITY_GROUP}}|sg-xxxxxxxx|g" \
    ecs/service-definition.json > /tmp/service-def.json

# 7. Create ECS service
aws ecs create-service \
  --cli-input-json file:///tmp/service-def.json \
  --region $AWS_REGION

# 8. Wait for stability
aws ecs wait services-stable \
  --cluster $CLUSTER_NAME \
  --services dashboard-app-service \
  --region $AWS_REGION
```

---

## Configuration Management

### Environment Variables

The application reads configuration from environment variables at runtime. Set these in the ECS task definition `environment` array:

| Variable | Default | Description |
|---|---|---|
| `SPRING_PROFILES_ACTIVE` | `docker` | Active Spring profile |
| `SERVER_PORT` | `8080` | Application HTTP port |
| `JAVA_OPTS` | See Dockerfile | JVM tuning flags |
| `TZ` | `UTC` | Container timezone |
| `SPRING_APPLICATION_NAME` | `dashboard-app` | Application name |

### Spring Profiles

Create profile-specific configuration files for different environments:

```
src/main/resources/
├── application.properties          # Base configuration
├── application-docker.properties   # Docker/container overrides
├── application-staging.properties  # Staging environment
└── application-production.properties # Production environment
```

Set `SPRING_PROFILES_ACTIVE` in the ECS task definition to activate the appropriate profile.

---

## Security Considerations

1. **Non-root user**: The container runs as `appuser` (non-root) for security.
2. **No secrets in images**: Never bake credentials into Docker images. Use ECS Secrets Manager integration.
3. **Security Groups**: Restrict inbound traffic to only required ports (8080 from ALB, not from internet directly).
4. **IAM Least Privilege**: Grant only the minimum required permissions to the task role.
5. **ECR Image Scanning**: Enable ECR image scanning to detect vulnerabilities.
6. **VPC Isolation**: Deploy tasks in private subnets with NAT Gateway for outbound internet access.

### Secrets Management

For sensitive configuration (database passwords, API keys), use AWS Secrets Manager:

```json
"secrets": [
  {
    "name": "DB_PASSWORD",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789:secret:dashboard-app/db-password"
  }
]
```

---

## ECS Fargate Scaling and Management

### Manual Scaling

```bash
# Scale to 4 tasks
aws ecs update-service \
  --cluster dashboard-app-cluster \
  --service dashboard-app-service \
  --desired-count 4 \
  --region us-east-1
```

### Auto Scaling

```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/dashboard-app-cluster/dashboard-app-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10

# Create CPU-based scaling policy
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/dashboard-app-cluster/dashboard-app-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name dashboard-app-cpu-scaling \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }'
```

### Blue/Green Deployments

For zero-downtime deployments, use AWS CodeDeploy with ECS:

1. Update the task definition with the new image
2. CodeDeploy shifts traffic from the blue (current) to green (new) target group
3. Rollback is instant if health checks fail

---

## ECS-Specific Troubleshooting

### Task Fails to Start

```bash
# Check stopped task details
aws ecs describe-tasks \
  --cluster dashboard-app-cluster \
  --tasks <task-arn> \
  --region us-east-1 \
  --query "tasks[0].{Status:lastStatus,StopCode:stopCode,StopReason:stoppedReason,Containers:containers[*].{Name:name,Reason:reason,ExitCode:exitCode}}"
```

Common causes:
- **Image pull failure**: Check ECR permissions and image URI
- **OOM killed**: Increase task memory in task definition
- **Port conflict**: Ensure containerPort matches application port
- **Missing execution role**: Attach `AmazonECSTaskExecutionRolePolicy`

### View Application Logs

```bash
# Stream logs from CloudWatch
aws logs tail /ecs/dashboard-app --follow --region us-east-1

# Get recent log events
aws logs get-log-events \
  --log-group-name /ecs/dashboard-app \
  --log-stream-name ecs/dashboard-app/<task-id> \
  --region us-east-1
```

### Service Not Reaching Desired Count

```bash
# Check service events
aws ecs describe-services \
  --cluster dashboard-app-cluster \
  --services dashboard-app-service \
  --region us-east-1 \
  --query "services[0].events[:10]"
```

Common causes:
- **Health check failures**: Verify `/api/health` returns HTTP 200
- **Network issues**: Check security group allows traffic on port 8080
- **Subnet routing**: Ensure subnets have route to internet (for ECR image pull)
- **CPU/Memory**: Verify valid Fargate CPU/memory combination

### Invalid CPU/Memory Combination

If you see `InvalidParameterException: Invalid CPU or Memory value`, use only valid combinations:
- CPU 512 → Memory must be 1024, 2048, 3072, or 4096

### Network Connectivity Issues

```bash
# Verify security group allows port 8080
aws ec2 describe-security-groups \
  --group-ids sg-xxxxxxxx \
  --query "SecurityGroups[0].IpPermissions"

# Check subnet has internet gateway or NAT gateway route
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=subnet-xxxxxxxx"
```

---

## Java-Specific Notes

### JVM Memory Tuning

The container uses these JVM flags (set via `JAVA_OPTS`):

```
-XX:+UseContainerSupport      # JVM respects cgroup memory limits
-XX:MaxRAMPercentage=75.0     # Use 75% of container memory for heap
-Xms256m                      # Initial heap: 256 MB
-Xmx512m                      # Max heap: 512 MB
-XX:+UseG1GC                  # G1 garbage collector
-Djava.security.egd=file:/dev/./urandom  # Faster SecureRandom
-Dfile.encoding=UTF-8         # UTF-8 encoding
-Duser.timezone=UTC           # UTC timezone
```

For a 1024 MB Fargate task, the JVM will use up to ~768 MB for heap (75%).

### Spring Boot Actuator

To add comprehensive health monitoring, add the Actuator dependency to `pom.xml`:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

Then configure in `application.properties`:

```properties
management.endpoints.web.exposure.include=health,info,metrics
management.endpoint.health.show-details=always
```

This exposes `/actuator/health`, `/actuator/info`, and `/actuator/metrics`.

### Graceful Shutdown

Spring Boot 2.3+ supports graceful shutdown. Add to `application.properties`:

```properties
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
```

ECS sends `SIGTERM` to the container before stopping it. The JVM catches this signal and Spring Boot completes in-flight requests before shutting down.

---

## Monitoring and Observability

### CloudWatch Metrics

ECS automatically publishes metrics to CloudWatch:
- `CPUUtilization` — CPU usage percentage
- `MemoryUtilization` — Memory usage percentage
- `RunningTaskCount` — Number of running tasks

### Application Metrics with Micrometer

Add Micrometer to `pom.xml` for JVM and application metrics:

```xml
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-cloudwatch2</artifactId>
</dependency>
```

### Distributed Tracing

Add AWS X-Ray for distributed tracing:

```xml
<dependency>
    <groupId>com.amazonaws</groupId>
    <artifactId>aws-xray-recorder-sdk-spring</artifactId>
    <version>2.14.0</version>
</dependency>
```

---

## Quick Reference

```bash
# Build and push image
./scripts/build-push.sh

# Deploy to ECS Fargate
./scripts/deploy-image.sh

# Check service status
aws ecs describe-services \
  --cluster dashboard-app-cluster \
  --services dashboard-app-service \
  --region us-east-1

# View logs
aws logs tail /ecs/dashboard-app --follow --region us-east-1

# Scale service
aws ecs update-service \
  --cluster dashboard-app-cluster \
  --service dashboard-app-service \
  --desired-count 3 \
  --region us-east-1

# Force new deployment (rolling update)
aws ecs update-service \
  --cluster dashboard-app-cluster \
  --service dashboard-app-service \
  --force-new-deployment \
  --region us-east-1
```
