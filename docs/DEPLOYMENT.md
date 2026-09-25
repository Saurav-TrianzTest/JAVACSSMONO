# dashboard-app — AWS ECS Fargate Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Local Development with Docker Compose](#local-development-with-docker-compose)
5. [Build and Push Docker Image](#build-and-push-docker-image)
6. [AWS ECS Fargate Prerequisites](#aws-ecs-fargate-prerequisites)
7. [ECS Task Definition Explained](#ecs-task-definition-explained)
8. [ECS Service Configuration](#ecs-service-configuration)
9. [ECS Fargate Deployment Walkthrough](#ecs-fargate-deployment-walkthrough)
10. [ECS-Specific Troubleshooting](#ecs-specific-troubleshooting)
11. [ECS Fargate Scaling and Management](#ecs-fargate-scaling-and-management)
12. [Configuration Management](#configuration-management)
13. [Security Considerations](#security-considerations)
14. [Java-Specific Notes](#java-specific-notes)

---

## Overview

**Application**: dashboard-app  
**Framework**: Spring Boot 3.2.5  
**Java Version**: 17  
**Build Tool**: Maven  
**Package Type**: Executable JAR  
**Application Port**: 8080  
**Health Endpoint**: `/api/health`  
**Target Platform**: AWS ECS Fargate  

---

## Prerequisites

### Local Development
| Tool | Version | Purpose |
|------|---------|---------|
| Docker Desktop | 24.x+ | Build and run containers locally |
| Docker Compose | 2.x+ | Multi-container local orchestration |
| Java JDK | 17+ | Local development (optional if using Docker) |
| Maven | 3.9.x+ | Local builds (optional if using Docker) |

### AWS Deployment
| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | 2.x+ | Interact with AWS services |
| Docker | 24.x+ | Build and push images |
| Python 3 | 3.8+ | Used by deploy-image.sh for JSON manipulation |

---

## Project Structure

```
JAVACSSMONO/
├── Dockerfile                    # Multi-stage build (Maven builder + JDK runtime)
├── .dockerignore                 # Excludes build artefacts and wrapper scripts
├── docker-compose.yml            # Local development orchestration
├── pom.xml                       # Maven project descriptor
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
│   └── service-definition.json   # ECS Fargate service definition
├── scripts/
│   ├── build-push.sh             # Linux/macOS: build & push to ECR or Docker Hub
│   ├── build-push.bat            # Windows: build & push to ECR or Docker Hub
│   ├── deploy-image.sh           # Linux/macOS: deploy to ECS Fargate
│   └── deploy-image.bat          # Windows: deploy to ECS Fargate
└── docs/
    └── DEPLOYMENT.md             # This file
```

---

## Local Development with Docker Compose

### 1. Build and start the application

```bash
# From the repository root
docker compose up --build
```

### 2. Verify the application is running

```bash
curl http://localhost:8080/api/health
# Expected: {"status":"ok"}
```

### 3. View logs

```bash
docker compose logs -f dashboard-app
```

### 4. Stop the application

```bash
docker compose down
```

### Environment Variables (docker-compose.yml)

| Variable | Default | Description |
|----------|---------|-------------|
| `JAVA_OPTS` | `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 ...` | JVM tuning flags |
| `SPRING_PROFILES_ACTIVE` | `docker` | Active Spring profile |
| `TZ` | `UTC` | Container timezone |

---

## Build and Push Docker Image

### Linux / macOS

```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

### Windows

```cmd
scripts\build-push.bat
```

### What the script does

1. Prompts for image tag (defaults to `latest`)
2. Prompts for registry type: **AWS ECR** or **Docker Hub**
3. For ECR: retrieves Account ID automatically, creates repository if it doesn't exist
4. Builds the Docker image from the repository root
5. Pushes the image to the selected registry

### Manual build (ECR example)

```bash
# Authenticate with ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789.dkr.ecr.us-east-1.amazonaws.com

# Build
docker build -t 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest .

# Push
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest
```

---

## AWS ECS Fargate Prerequisites

### 1. AWS CLI Configuration

```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region, Output format
```

### 2. VPC and Networking

- **VPC**: A VPC with at least 2 subnets in different Availability Zones
- **Subnets**: Public or private subnets (public required if `assignPublicIp: ENABLED`)
- **Security Group**: Must allow inbound TCP on port **8080** from the load balancer or internet

```bash
# Create a security group (example)
aws ec2 create-security-group \
  --group-name dashboard-app-sg \
  --description "Security group for dashboard-app ECS tasks" \
  --vpc-id vpc-xxxxxxxx

# Allow inbound on port 8080
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0
```

### 3. IAM Roles

#### ECS Task Execution Role (`ecsTaskExecutionRole`)
Allows ECS to pull images from ECR and write logs to CloudWatch.

```bash
# Create the role
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

#### ECS Task Role (`ecsTaskRole`)
Grants the application container permissions to call AWS services.

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

### 4. CloudWatch Log Group

```bash
aws logs create-log-group \
  --log-group-name /ecs/dashboard-app \
  --region us-east-1
```

### 5. ECR Repository

```bash
aws ecr create-repository \
  --repository-name dashboard-app \
  --region us-east-1
```

---

## ECS Task Definition Explained

File: `ecs/task-definition.json`

| Field | Value | Notes |
|-------|-------|-------|
| `family` | `dashboard-app-task` | Task definition family name |
| `requiresCompatibilities` | `["FARGATE"]` | Fargate launch type |
| `networkMode` | `awsvpc` | Required for Fargate |
| `cpu` | `"512"` | 0.5 vCPU |
| `memory` | `"1024"` | 1 GB RAM |
| `executionRoleArn` | `ecsTaskExecutionRole` | ECR pull + CloudWatch logs |
| `taskRoleArn` | `ecsTaskRole` | Application AWS permissions |

### Valid Fargate CPU/Memory Combinations

| CPU | Valid Memory Values |
|-----|-------------------|
| 256 (.25 vCPU) | 512, 1024, 2048 MB |
| **512 (.5 vCPU)** | **1024**, 2048, 3072, 4096 MB |
| 1024 (1 vCPU) | 2048–8192 MB |
| 2048 (2 vCPU) | 4096–16384 MB |
| 4096 (4 vCPU) | 8192–30720 MB |

### Container Definition

```json
{
  "name": "dashboard-app",
  "image": "{{IMAGE_URI}}",
  "essential": true,
  "portMappings": [{"containerPort": 8080, "protocol": "tcp"}],
  "environment": [
    {"name": "SPRING_PROFILES_ACTIVE", "value": "docker"},
    {"name": "TZ", "value": "UTC"},
    {"name": "JAVA_OPTS", "value": "-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 ..."}
  ],
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/dashboard-app",
      "awslogs-region": "{{AWS_REGION}}",
      "awslogs-stream-prefix": "ecs"
    }
  }
}
```

---

## ECS Service Configuration

File: `ecs/service-definition.json`

| Field | Value | Notes |
|-------|-------|-------|
| `serviceName` | `dashboard-app-service` | ECS service name |
| `launchType` | `FARGATE` | Serverless compute |
| `desiredCount` | `2` | Number of running tasks |
| `assignPublicIp` | `ENABLED` | Required for public subnets |
| `maximumPercent` | `200` | Rolling deployment ceiling |
| `minimumHealthyPercent` | `50` | Rolling deployment floor |

---

## ECS Fargate Deployment Walkthrough

### Step 1: Build and push the image

```bash
./scripts/build-push.sh
# Select: 1 (AWS ECR)
# Enter region, tag, etc.
```

### Step 2: Deploy to ECS Fargate

```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

The script will prompt for:
- AWS Region
- ECS Cluster name
- ECR Image URI
- VPC ID
- Subnet IDs (comma-separated)
- Security Group ID
- Whether to create an Application Load Balancer

### Step 3: Verify the deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster dashboard-app-cluster \
  --services dashboard-app-service \
  --region us-east-1

# List running tasks
aws ecs list-tasks \
  --cluster dashboard-app-cluster \
  --service-name dashboard-app-service \
  --region us-east-1

# View application logs
aws logs tail /ecs/dashboard-app --follow --region us-east-1
```

### Step 4: Test the health endpoint

```bash
# If using ALB
curl http://<ALB_DNS>/api/health

# If using public IP (get from task ENI)
TASK_ARN=$(aws ecs list-tasks --cluster dashboard-app-cluster \
  --service-name dashboard-app-service --query "taskArns[0]" --output text)
ENI_ID=$(aws ecs describe-tasks --cluster dashboard-app-cluster \
  --tasks $TASK_ARN --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" \
  --output text)
PUBLIC_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID \
  --query "NetworkInterfaces[0].Association.PublicIp" --output text)
curl http://$PUBLIC_IP:8080/api/health
```

---

## ECS-Specific Troubleshooting

### Task fails to start

```bash
# Check stopped task reason
aws ecs describe-tasks \
  --cluster dashboard-app-cluster \
  --tasks <TASK_ARN> \
  --query "tasks[0].stoppedReason"

# Check container exit code
aws ecs describe-tasks \
  --cluster dashboard-app-cluster \
  --tasks <TASK_ARN> \
  --query "tasks[0].containers[0].{ExitCode:exitCode,Reason:reason}"
```

**Common causes:**
- `CannotPullContainerError`: ECR permissions issue — verify `ecsTaskExecutionRole` has ECR pull permissions
- `OutOfMemoryError`: Increase task memory in `task-definition.json`
- `ResourceInitializationError`: Check subnet internet access (NAT Gateway or public IP)

### Network connectivity issues

```bash
# Verify security group allows inbound on port 8080
aws ec2 describe-security-groups --group-ids sg-xxxxxxxx \
  --query "SecurityGroups[0].IpPermissions"

# Check task ENI and public IP
aws ecs describe-tasks --cluster dashboard-app-cluster \
  --tasks <TASK_ARN> \
  --query "tasks[0].attachments"
```

### CPU/Memory errors

```
ClientException: CPU value must be one of [256, 512, 1024, 2048, 4096]
```
→ Ensure `cpu` in `task-definition.json` is one of the valid string values.

```
ClientException: Memory value must be between X and Y for CPU value Z
```
→ Use a valid CPU/memory combination from the table above.

### JVM startup issues

Spring Boot with JVM can take 30–60 seconds to start. If health checks fail:
- Increase `startPeriod` in health check configuration
- Check CloudWatch logs for startup errors:
  ```bash
  aws logs tail /ecs/dashboard-app --follow --region us-east-1
  ```

### Service not stabilizing

```bash
# Check service events
aws ecs describe-services \
  --cluster dashboard-app-cluster \
  --services dashboard-app-service \
  --query "services[0].events[:5]"
```

---

## ECS Fargate Scaling and Management

### Manual scaling

```bash
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

### Blue/Green Deployment with CodeDeploy

1. Install the CodeDeploy agent (not required for ECS)
2. Create a CodeDeploy application and deployment group targeting the ECS service
3. Use `appspec.yaml` to define the deployment lifecycle
4. Trigger deployments via CodePipeline or CLI

### Rolling Update (default)

The service definition uses:
- `maximumPercent: 200` — allows double the desired count during deployment
- `minimumHealthyPercent: 50` — keeps at least half the tasks running

---

## Configuration Management

### Environment Variables

Override environment variables at deployment time by editing `ecs/task-definition.json` before running `deploy-image.sh`, or by using AWS Systems Manager Parameter Store / Secrets Manager:

```json
"secrets": [
  {
    "name": "DATABASE_PASSWORD",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789:secret:dashboard-app/db-password"
  }
]
```

### Spring Profiles

The container runs with `SPRING_PROFILES_ACTIVE=docker`. Create `application-docker.properties` or `application-docker.yml` for Docker/ECS-specific configuration:

```properties
# src/main/resources/application-docker.properties
spring.datasource.url=${DATABASE_URL:jdbc:h2:mem:testdb}
logging.level.com.trianz=INFO
```

---

## Security Considerations

1. **Non-root user**: The Dockerfile creates and uses a non-root `appuser` account
2. **No secrets in images**: Use AWS Secrets Manager or SSM Parameter Store for sensitive values
3. **Minimal runtime image**: `eclipse-temurin:17-jdk` — no build tools in production
4. **Security Group**: Restrict inbound access to only required ports (8080)
5. **IAM least privilege**: Grant only the permissions the application needs in `ecsTaskRole`
6. **ECR image scanning**: Enable ECR image scanning on push:
   ```bash
   aws ecr put-image-scanning-configuration \
     --repository-name dashboard-app \
     --image-scanning-configuration scanOnPush=true
   ```
7. **VPC isolation**: Deploy tasks in private subnets with a NAT Gateway for outbound traffic

---

## Java-Specific Notes

### JVM Tuning for Containers

The following JVM flags are set via `JAVA_OPTS`:

| Flag | Purpose |
|------|---------|
| `-XX:+UseContainerSupport` | Enables JVM container awareness (reads cgroup limits) |
| `-XX:MaxRAMPercentage=75.0` | Limits heap to 75% of container memory (768 MB for 1 GB task) |
| `-XX:+UseG1GC` | G1 garbage collector — good balance for web applications |
| `-Djava.security.egd=file:/dev/./urandom` | Faster random number generation in containers |
| `-Dfile.encoding=UTF-8` | Consistent character encoding |
| `-Duser.timezone=UTC` | Consistent timezone |

### Spring Boot Graceful Shutdown

The Dockerfile uses `exec java $JAVA_OPTS -jar /app/app.jar` (exec form) so that SIGTERM is forwarded directly to the JVM. Add to `application.properties` for graceful shutdown:

```properties
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
```

### Heap Size Recommendation

For the default Fargate task (512 CPU / 1024 MB memory):
- Container memory: 1024 MB
- JVM heap (75%): ~768 MB
- OS + JVM overhead: ~256 MB

To increase memory, update `task-definition.json`:
```json
"cpu": "1024",
"memory": "2048"
```

### Monitoring with JMX

To enable JMX monitoring, add to `JAVA_OPTS`:
```
-Dcom.sun.management.jmxremote
-Dcom.sun.management.jmxremote.port=9090
-Dcom.sun.management.jmxremote.rmi.port=9090
-Dcom.sun.management.jmxremote.authenticate=false
-Dcom.sun.management.jmxremote.ssl=false
-Djava.rmi.server.hostname=0.0.0.0
```

### Adding Spring Boot Actuator

For richer health and metrics endpoints, add to `pom.xml`:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

Then configure in `application.properties`:
```properties
management.endpoints.web.exposure.include=health,info,metrics,prometheus
management.endpoint.health.show-details=always
```

This exposes `/actuator/health` for health checks and `/actuator/metrics` for monitoring.
