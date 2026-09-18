# dashboard-app — AWS ECS Fargate Deployment Guide

**Application**: dashboard-app  
**Framework**: Spring Boot 3.2.5  
**Java Version**: 17  
**Build Tool**: Maven  
**Target Platform**: AWS ECS Fargate  
**Container Port**: 8080  
**Health Endpoint**: `/api/health`

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Project Structure](#2-project-structure)
3. [Local Development with Docker Compose](#3-local-development-with-docker-compose)
4. [Build and Push Docker Image](#4-build-and-push-docker-image)
5. [AWS ECS Fargate Prerequisites](#5-aws-ecs-fargate-prerequisites)
6. [ECS Task Definition Explained](#6-ecs-task-definition-explained)
7. [ECS Service Configuration](#7-ecs-service-configuration)
8. [ECS Fargate Deployment Walkthrough](#8-ecs-fargate-deployment-walkthrough)
9. [ECS-Specific Troubleshooting](#9-ecs-specific-troubleshooting)
10. [ECS Fargate Scaling and Management](#10-ecs-fargate-scaling-and-management)
11. [Configuration Management](#11-configuration-management)
12. [Security Considerations](#12-security-considerations)
13. [Java-Specific Notes](#13-java-specific-notes)

---

## 1. Prerequisites

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
| AWS Account | — | Target deployment environment |
| IAM permissions | — | ECS, ECR, CloudWatch, ELB access |

### Install AWS CLI
```bash
# macOS
brew install awscli

# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# Windows
# Download from https://aws.amazon.com/cli/
```

### Configure AWS CLI
```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region, Output format
```

---

## 2. Project Structure

```
AWS ECS CMP/
├── Dockerfile                    # Multi-stage build (Maven builder + Corretto 17 runtime)
├── docker-compose.yml            # Local development (application only)
├── .dockerignore                 # Excludes build artefacts and wrapper files
├── pom.xml                       # Maven project descriptor
├── src/
│   └── main/
│       ├── java/com/trianz/dashboard/
│       │   ├── DashboardApplication.java   # Spring Boot entry point
│       │   ├── controller/HealthController.java  # GET /api/health
│       │   └── service/HealthService.java
│       └── resources/
│           └── application.properties      # server.port=8080
├── ecs/
│   ├── task-definition.json      # ECS Fargate task definition
│   └── service-definition.json   # ECS Fargate service definition
├── scripts/
│   ├── build-push.sh             # Linux/macOS: build and push to ECR/Docker Hub
│   ├── build-push.bat            # Windows: build and push to ECR/Docker Hub
│   ├── deploy-image.sh           # Linux/macOS: deploy to ECS Fargate
│   └── deploy-image.bat          # Windows: deploy to ECS Fargate
└── docs/
    └── DEPLOYMENT.md             # This file
```

---

## 3. Local Development with Docker Compose

### Build and Start
```bash
# Build the image and start the application
docker compose up --build

# Run in detached mode
docker compose up --build -d

# View logs
docker compose logs -f dashboard-app
```

### Verify the Application
```bash
# Health check
curl http://localhost:8080/api/health
# Expected: {"status":"ok"}
```

### Stop the Application
```bash
docker compose down

# Remove volumes too
docker compose down -v
```

### Environment Variables (Local)
Edit `docker-compose.yml` to override environment variables:
```yaml
environment:
  SPRING_PROFILES_ACTIVE: docker
  JAVA_OPTS: "-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Xmx512m"
```

---

## 4. Build and Push Docker Image

### Linux / macOS
```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

### Windows
```cmd
scripts\build-push.bat
```

The script will prompt you to:
1. Enter an image tag (default: `latest`)
2. Select registry type:
   - **Option 1**: AWS ECR — prompts for region, account ID, repository name
   - **Option 2**: Docker Hub — prompts for username, password, namespace

The script automatically:
- Sanitises the image name (lowercase, hyphens)
- Authenticates with the selected registry
- Creates the ECR repository if it does not exist (ECR only)
- Builds the Docker image from the project root
- Pushes the image to the registry

### Manual Build
```bash
# Build
docker build -t dashboard-app:latest .

# Tag for ECR
docker tag dashboard-app:latest \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest

# Push to ECR
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    123456789012.dkr.ecr.us-east-1.amazonaws.com

docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest
```

---

## 5. AWS ECS Fargate Prerequisites

### 5.1 IAM Roles

#### ECS Task Execution Role
Required for ECS to pull images from ECR and write logs to CloudWatch.

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

#### ECS Task Role (Optional)
Required if the application needs to call other AWS services (S3, DynamoDB, etc.).

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

### 5.2 VPC and Networking

Fargate tasks require a VPC with at least two subnets (for high availability).

```bash
# List available VPCs
aws ec2 describe-vpcs --query "Vpcs[*].{VpcId:VpcId,CIDR:CidrBlock,Default:IsDefault}"

# List subnets in a VPC
aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=vpc-xxxxxxxx" \
  --query "Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock}"
```

### 5.3 Security Group

Create a security group that allows inbound traffic on port 8080:

```bash
# Create security group
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

# Allow inbound on port 80 (if using ALB)
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxxxxx \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0
```

### 5.4 ECR Repository

```bash
# Create ECR repository
aws ecr create-repository \
  --repository-name dashboard-app \
  --region us-east-1 \
  --image-scanning-configuration scanOnPush=true

# Get repository URI
aws ecr describe-repositories \
  --repository-names dashboard-app \
  --query "repositories[0].repositoryUri"
```

### 5.5 CloudWatch Log Group

```bash
aws logs create-log-group \
  --log-group-name /ecs/dashboard-app \
  --region us-east-1

# Set retention (optional)
aws logs put-retention-policy \
  --log-group-name /ecs/dashboard-app \
  --retention-in-days 30
```

---

## 6. ECS Task Definition Explained

The task definition (`ecs/task-definition.json`) configures how the container runs on Fargate.

### Key Fields

| Field | Value | Description |
|-------|-------|-------------|
| `family` | `dashboard-app-task` | Task definition family name |
| `requiresCompatibilities` | `["FARGATE"]` | Must be FARGATE for serverless containers |
| `networkMode` | `awsvpc` | Required for Fargate; each task gets its own ENI |
| `cpu` | `"512"` | 0.5 vCPU (valid Fargate unit) |
| `memory` | `"1024"` | 1 GB RAM (valid for 512 CPU) |
| `executionRoleArn` | `ecsTaskExecutionRole` | Allows ECS to pull images and write logs |

### Valid Fargate CPU/Memory Combinations

| CPU | Valid Memory Values |
|-----|-------------------|
| 256 (.25 vCPU) | 512, 1024, 2048 MB |
| **512 (.5 vCPU)** | **1024, 2048, 3072, 4096 MB** ← Used here |
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
    {"name": "JAVA_OPTS", "value": "-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"}
  ],
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/dashboard-app",
      "awslogs-region": "us-east-1",
      "awslogs-stream-prefix": "ecs"
    }
  }
}
```

---

## 7. ECS Service Configuration

The service definition (`ecs/service-definition.json`) controls how tasks are scheduled and maintained.

### Key Fields

| Field | Value | Description |
|-------|-------|-------------|
| `launchType` | `FARGATE` | Serverless container execution |
| `desiredCount` | `2` | Number of running task replicas |
| `networkMode` | `awsvpc` | Each task gets its own private IP |
| `assignPublicIp` | `ENABLED` | Required if tasks need internet access |
| `maximumPercent` | `200` | Allow 2x tasks during rolling deployment |
| `minimumHealthyPercent` | `50` | Keep at least 50% healthy during deployment |

### Network Configuration
```json
"networkConfiguration": {
  "awsvpcConfiguration": {
    "subnets": ["subnet-aaa", "subnet-bbb"],
    "securityGroups": ["sg-xxxxxxxx"],
    "assignPublicIp": "ENABLED"
  }
}
```

---

## 8. ECS Fargate Deployment Walkthrough

### Step 1: Push Image to ECR
```bash
./scripts/build-push.sh
# Select option 1 (AWS ECR)
# Enter your region, account ID, and repository name
```

### Step 2: Deploy to ECS Fargate
```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

The deployment script will:
1. Prompt for AWS region, cluster name, image URI, VPC, subnets, security group
2. Retrieve your AWS Account ID automatically
3. Create the CloudWatch log group if it doesn't exist
4. Create the ECS cluster if it doesn't exist
5. Optionally create an Application Load Balancer and Target Group
6. Replace all `{{PLACEHOLDER}}` values in the JSON files
7. Register the task definition
8. Create or update the ECS service
9. Wait for the service to reach a stable state
10. Display deployment summary

### Step 3: Verify Deployment
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

### Step 4: Access the Application
```bash
# If using ALB, get the DNS name
aws elbv2 describe-load-balancers \
  --names dashboard-app-alb \
  --query "LoadBalancers[0].DNSName" \
  --output text

# Test health endpoint
curl http://<ALB_DNS>/api/health
# Expected: {"status":"ok"}
```

### Manual Deployment (Without Script)
```bash
# 1. Replace placeholders in task definition
sed -i 's|{{IMAGE_URI}}|123456789012.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest|g' ecs/task-definition.json
sed -i 's|{{AWS_REGION}}|us-east-1|g' ecs/task-definition.json
sed -i 's|{{ACCOUNT_ID}}|123456789012|g' ecs/task-definition.json

# 2. Register task definition
aws ecs register-task-definition \
  --cli-input-json file://ecs/task-definition.json \
  --region us-east-1

# 3. Create service
aws ecs create-service \
  --cli-input-json file://ecs/service-definition.json \
  --region us-east-1
```

---

## 9. ECS-Specific Troubleshooting

### Task Fails to Start

**Symptom**: Tasks stop immediately after starting.

```bash
# Check stopped task reason
aws ecs describe-tasks \
  --cluster dashboard-app-cluster \
  --tasks <TASK_ARN> \
  --region us-east-1 \
  --query "tasks[0].{Status:lastStatus,StopReason:stoppedReason,Containers:containers[*].{Name:name,Reason:reason,ExitCode:exitCode}}"
```

**Common causes**:
- `CannotPullContainerError`: ECR authentication failed or image not found
- `OutOfMemoryError`: Increase task memory in task definition
- Application crash: Check CloudWatch logs

### Cannot Pull Container Image

```bash
# Verify ECR repository exists
aws ecr describe-repositories --repository-names dashboard-app

# Verify image exists
aws ecr list-images --repository-name dashboard-app

# Verify execution role has ECR permissions
aws iam get-role-policy --role-name ecsTaskExecutionRole --policy-name ECRAccess
```

### Network Connectivity Issues

```bash
# Verify security group allows inbound on port 8080
aws ec2 describe-security-groups --group-ids sg-xxxxxxxx

# Verify subnets have route to internet (for public IP)
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=subnet-xxxxxxxx"
```

### CloudWatch Logs Not Appearing

```bash
# Verify log group exists
aws logs describe-log-groups --log-group-name-prefix /ecs/dashboard-app

# Check execution role has CloudWatch permissions
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:role/ecsTaskExecutionRole \
  --action-names logs:CreateLogStream logs:PutLogEvents
```

### Invalid CPU/Memory Combination

**Error**: `Invalid CPU or memory value specified`

Ensure you use valid Fargate combinations. The task definition uses `cpu: "512"` and `memory: "1024"` which is valid.

### Service Not Reaching Desired Count

```bash
# Check service events
aws ecs describe-services \
  --cluster dashboard-app-cluster \
  --services dashboard-app-service \
  --query "services[0].events[0:5]"
```

---

## 10. ECS Fargate Scaling and Management

### Manual Scaling
```bash
# Scale up to 4 tasks
aws ecs update-service \
  --cluster dashboard-app-cluster \
  --service dashboard-app-service \
  --desired-count 4 \
  --region us-east-1

# Scale down to 0 (stop all tasks)
aws ecs update-service \
  --cluster dashboard-app-cluster \
  --service dashboard-app-service \
  --desired-count 0 \
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

### Rolling Deployment (Blue/Green)
```bash
# Update service with new image
aws ecs update-service \
  --cluster dashboard-app-cluster \
  --service dashboard-app-service \
  --task-definition dashboard-app-task:NEW_REVISION \
  --region us-east-1

# Monitor rollout
aws ecs wait services-stable \
  --cluster dashboard-app-cluster \
  --services dashboard-app-service \
  --region us-east-1
```

### Force New Deployment
```bash
aws ecs update-service \
  --cluster dashboard-app-cluster \
  --service dashboard-app-service \
  --force-new-deployment \
  --region us-east-1
```

---

## 11. Configuration Management

### Environment Variables in Task Definition
Add environment variables to `ecs/task-definition.json`:
```json
"environment": [
  {"name": "SPRING_PROFILES_ACTIVE", "value": "production"},
  {"name": "DATABASE_URL", "value": "jdbc:postgresql://db-host:5432/dashboard"}
]
```

### Secrets from AWS Secrets Manager
For sensitive values, use the `secrets` field:
```json
"secrets": [
  {
    "name": "DATABASE_PASSWORD",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:dashboard-app/db-password"
  }
]
```

### Spring Boot Profiles
The application uses `SPRING_PROFILES_ACTIVE=docker` in containers. Create `application-docker.properties` for Docker-specific overrides:
```properties
# src/main/resources/application-docker.properties
logging.level.root=INFO
management.endpoints.web.exposure.include=health,info
```

---

## 12. Security Considerations

### Container Security
- ✅ Application runs as non-root user (`appuser`, UID 1001)
- ✅ No unnecessary packages installed in runtime image
- ✅ Multi-stage build — no build tools in production image
- ✅ Amazon Corretto 17 base image (AWS-maintained, security-patched)

### Network Security
- Use private subnets with NAT Gateway for production workloads
- Restrict security group inbound rules to ALB security group only
- Enable VPC Flow Logs for network traffic auditing

### IAM Security
- Use least-privilege IAM policies for task execution and task roles
- Rotate IAM credentials regularly
- Use AWS Secrets Manager for sensitive configuration values

### Image Security
- Enable ECR image scanning on push
- Use specific image tags (not `latest`) in production
- Regularly update base images for security patches

### Secrets Management
```bash
# Store a secret
aws secretsmanager create-secret \
  --name dashboard-app/production/db-password \
  --secret-string "your-secure-password"

# Reference in task definition
# "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789012:secret:dashboard-app/production/db-password"
```

---

## 13. Java-Specific Notes

### JVM Configuration for Containers

The Dockerfile sets the following JVM flags via `JAVA_OPTS`:

| Flag | Purpose |
|------|---------|
| `-XX:+UseContainerSupport` | Honour cgroup CPU/memory limits (Java 10+) |
| `-XX:MaxRAMPercentage=75.0` | Use up to 75% of container memory for heap |
| `-XX:+UseG1GC` | G1 garbage collector (default in Java 17) |
| `-Djava.security.egd=file:/dev/./urandom` | Faster SecureRandom seeding |

### Memory Sizing

With `memory: "1024"` MB in the task definition and `MaxRAMPercentage=75.0`:
- **Max heap**: ~768 MB
- **Non-heap** (metaspace, threads, etc.): ~256 MB

To increase memory, update the task definition to a valid Fargate combination (e.g., `cpu: "512"`, `memory: "2048"`).

### Spring Boot Startup Time

Spring Boot applications typically take 5–15 seconds to start. The ECS service health check grace period should be set to at least 60 seconds to avoid premature task termination.

### Graceful Shutdown

The Dockerfile uses `exec java $JAVA_OPTS -jar /app/app.jar` which ensures the JVM receives `SIGTERM` directly from ECS, enabling Spring Boot's graceful shutdown:

```properties
# application.properties
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
```

### Logging

Application logs are sent to CloudWatch Logs via the `awslogs` driver. View them with:
```bash
aws logs tail /ecs/dashboard-app --follow --region us-east-1
```

For structured JSON logging, add to `pom.xml`:
```xml
<dependency>
  <groupId>net.logstash.logback</groupId>
  <artifactId>logstash-logback-encoder</artifactId>
  <version>7.4</version>
</dependency>
```

### Spring Boot Actuator (Recommended)

Add Spring Boot Actuator for production-grade health monitoring:
```xml
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```

This exposes `/actuator/health`, `/actuator/info`, and `/actuator/metrics` endpoints.

---

*Generated for dashboard-app — Spring Boot 3.2.5 / Java 17 / AWS ECS Fargate*
