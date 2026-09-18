# Deployment Guide – dashboard-app on AWS EKS

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Local Development with Docker Compose](#local-development-with-docker-compose)
5. [Building and Pushing the Docker Image](#building-and-pushing-the-docker-image)
6. [AWS EKS Prerequisites](#aws-eks-prerequisites)
7. [EKS Cluster Setup](#eks-cluster-setup)
8. [Kubernetes Deployment Walkthrough](#kubernetes-deployment-walkthrough)
9. [Deploying with the Deployment Script](#deploying-with-the-deployment-script)
10. [Verifying the Deployment](#verifying-the-deployment)
11. [Scaling and Management](#scaling-and-management)
12. [Configuration Management](#configuration-management)
13. [Troubleshooting](#troubleshooting)
14. [Security Considerations](#security-considerations)
15. [Java-Specific Notes](#java-specific-notes)

---

## Overview

**Application**: `dashboard-app`  
**Framework**: Spring Boot 3.2.5  
**Java Version**: 17  
**Build Tool**: Maven  
**Package Type**: Executable JAR  
**Application Port**: 8080  
**Health Endpoint**: `GET /api/health`  
**Target Platform**: AWS EKS (Elastic Kubernetes Service)  
**Runtime Base Image**: `amazoncorretto:17`

---

## Prerequisites

### Local Development
| Tool | Version | Purpose |
|------|---------|---------|
| Docker Desktop | 24.x+ | Build and run containers |
| Docker Compose | 2.x+ | Local multi-container orchestration |
| Java JDK | 17+ | Local development and testing |
| Maven | 3.9.x+ | Build tool |

### AWS EKS Deployment
| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | 2.x+ | AWS authentication and ECR operations |
| kubectl | 1.28+ | Kubernetes cluster management |
| eksctl | 0.170+ | EKS cluster provisioning (optional) |
| Helm | 3.x+ | AWS Load Balancer Controller installation |

### AWS IAM Permissions Required
The IAM user/role executing deployments must have:
- `ecr:GetAuthorizationToken`
- `ecr:BatchCheckLayerAvailability`
- `ecr:PutImage`
- `ecr:InitiateLayerUpload`
- `ecr:UploadLayerPart`
- `ecr:CompleteLayerUpload`
- `ecr:CreateRepository`
- `ecr:DescribeRepositories`
- `eks:DescribeCluster`
- `eks:UpdateKubeconfig`

---

## Project Structure

```
AWSEKS2CMP/
├── src/
│   └── main/
│       ├── java/com/trianz/dashboard/
│       │   ├── DashboardApplication.java       # Spring Boot entry point
│       │   ├── controller/HealthController.java # GET /api/health endpoint
│       │   └── service/HealthService.java       # Health status logic
│       └── resources/
│           └── application.properties           # App configuration
├── kubernetes/
│   ├── namespace.yaml    # Kubernetes namespace
│   ├── deployment.yaml   # Deployment with 2 replicas
│   ├── service.yaml      # ClusterIP service
│   └── ingress.yaml      # ALB ingress
├── scripts/
│   ├── build-push.sh     # Linux/macOS build & push
│   ├── build-push.bat    # Windows build & push
│   ├── deploy-image.sh   # Linux/macOS EKS deploy
│   └── deploy-image.bat  # Windows EKS deploy
├── docs/
│   └── DEPLOYMENT.md     # This file
├── Dockerfile            # Multi-stage build
├── docker-compose.yml    # Local development
├── .dockerignore         # Docker build exclusions
└── pom.xml               # Maven build descriptor
```

---

## Local Development with Docker Compose

### 1. Build and Start the Application

```bash
# From the repository root
docker compose up --build
```

### 2. Verify the Application is Running

```bash
# Check health endpoint
curl http://localhost:8080/api/health
# Expected: {"status":"ok"}
```

### 3. View Application Logs

```bash
docker compose logs -f dashboard-app
```

### 4. Stop the Application

```bash
docker compose down
```

### Environment Variable Overrides

You can override environment variables at runtime:

```bash
SPRING_PROFILES_ACTIVE=prod docker compose up
```

Or create a `.env` file in the project root:

```env
SPRING_PROFILES_ACTIVE=prod
SERVER_PORT=8080
```

---

## Building and Pushing the Docker Image

### Linux / macOS

```bash
# Make the script executable (first time only)
chmod +x scripts/build-push.sh

# Run from repository root
bash scripts/build-push.sh
```

### Windows

```cmd
REM Run from repository root
scripts\build-push.bat
```

### Script Prompts

The script will interactively ask for:

1. **Image tag** – defaults to `latest`
2. **Registry type** – `1` for AWS ECR, `2` for Docker Hub
3. **Registry-specific details** (region, account ID, credentials)

### Manual Docker Build

```bash
# Build the image
docker build -t dashboard-app:latest .

# Tag for ECR
docker tag dashboard-app:latest \
  123456789012.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest

# Push to ECR
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:latest
```

---

## AWS EKS Prerequisites

### 1. Configure AWS CLI

```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region, Output format
```

### 2. Verify AWS Identity

```bash
aws sts get-caller-identity
```

### 3. Install AWS Load Balancer Controller

The ingress manifest uses the AWS Load Balancer Controller. Install it on your EKS cluster:

```bash
# Add the EKS chart repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the controller (replace <cluster-name> and <region>)
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<cluster-name> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

> **Note**: The AWS Load Balancer Controller requires an IAM role with appropriate permissions. See the [official documentation](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html).

---

## EKS Cluster Setup

### Option A: Use an Existing Cluster

```bash
# Configure kubectl to use your existing cluster
aws eks update-kubeconfig --region us-east-1 --name my-cluster

# Verify connectivity
kubectl cluster-info
kubectl get nodes
```

### Option B: Create a New Cluster with eksctl

```bash
eksctl create cluster \
  --name dashboard-cluster \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 4 \
  --managed
```

---

## Kubernetes Deployment Walkthrough

### Manifest Descriptions

| File | Kind | Purpose |
|------|------|---------|
| `namespace.yaml` | Namespace | Isolates `dashboard-app` resources |
| `deployment.yaml` | Deployment | Runs 2 replicas with rolling updates |
| `service.yaml` | Service (ClusterIP) | Internal load balancing on port 80 |
| `ingress.yaml` | Ingress (ALB) | External HTTPS access via AWS ALB |

### Deployment Configuration Highlights

- **Replicas**: 2 (for high availability)
- **Rolling Update**: `maxSurge: 1`, `maxUnavailable: 0` (zero-downtime)
- **Resource Requests**: CPU 250m, Memory 512Mi
- **Resource Limits**: CPU 500m, Memory 1Gi
- **Liveness Probe**: `GET /api/health` (starts after 60s, every 30s)
- **Readiness Probe**: `GET /api/health` (starts after 30s, every 15s)
- **Startup Probe**: `GET /api/health` (allows up to 120s for JVM startup)
- **Security**: Non-root user (UID 1000), all capabilities dropped

### Manual Manifest Application

```bash
# Apply in order
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# Wait for rollout
kubectl rollout status deployment/dashboard-app -n dashboard-app
```

> **Important**: Replace `{{IMAGE_URI}}` in `deployment.yaml` with your actual image URI before applying manually.

---

## Deploying with the Deployment Script

### Linux / macOS

```bash
# Make executable (first time only)
chmod +x scripts/deploy-image.sh

# Run from repository root
bash scripts/deploy-image.sh
```

### Windows

```cmd
scripts\deploy-image.bat
```

### Script Prompts

1. **AWS Region** – e.g., `us-east-1`
2. **EKS Cluster Name** – your cluster name
3. **Docker Image URI** – full image path with tag

The script will:
- Configure `kubectl` for your EKS cluster
- Substitute the image URI in the deployment manifest
- Apply all Kubernetes manifests in order
- Wait for the rollout to complete
- Display the application URL

---

## Verifying the Deployment

```bash
# Check all resources in the namespace
kubectl get all -n dashboard-app

# Check pod status
kubectl get pods -n dashboard-app

# View pod logs
kubectl logs -l app=dashboard-app -n dashboard-app --tail=100

# Describe a pod for events
kubectl describe pod -l app=dashboard-app -n dashboard-app

# Check ingress and get the ALB hostname
kubectl get ingress -n dashboard-app

# Test the health endpoint (replace <ALB_HOSTNAME>)
curl http://<ALB_HOSTNAME>/api/health
```

---

## Scaling and Management

### Manual Scaling

```bash
# Scale to 3 replicas
kubectl scale deployment dashboard-app --replicas=3 -n dashboard-app
```

### Horizontal Pod Autoscaler (HPA)

```bash
# Create HPA (scale between 2 and 10 pods at 70% CPU)
kubectl autoscale deployment dashboard-app \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n dashboard-app

# Check HPA status
kubectl get hpa -n dashboard-app
```

### Rolling Update (New Image)

```bash
# Update the image
kubectl set image deployment/dashboard-app \
  dashboard-app=<NEW_IMAGE_URI> \
  -n dashboard-app

# Monitor rollout
kubectl rollout status deployment/dashboard-app -n dashboard-app
```

### Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/dashboard-app -n dashboard-app

# Rollback to a specific revision
kubectl rollout history deployment/dashboard-app -n dashboard-app
kubectl rollout undo deployment/dashboard-app --to-revision=2 -n dashboard-app
```

---

## Configuration Management

### Environment Variables

Environment variables are defined in `kubernetes/deployment.yaml` under `spec.template.spec.containers[].env`.

To update a configuration value without rebuilding the image:

```bash
kubectl set env deployment/dashboard-app \
  SPRING_PROFILES_ACTIVE=production \
  -n dashboard-app
```

### Kubernetes Secrets (for sensitive values)

```bash
# Create a secret
kubectl create secret generic dashboard-app-secrets \
  --from-literal=DATABASE_PASSWORD=mysecretpassword \
  -n dashboard-app

# Reference in deployment.yaml
# env:
#   - name: DATABASE_PASSWORD
#     valueFrom:
#       secretKeyRef:
#         name: dashboard-app-secrets
#         key: DATABASE_PASSWORD
```

### ConfigMaps (for non-sensitive configuration)

```bash
# Create a ConfigMap from application.properties
kubectl create configmap dashboard-app-config \
  --from-file=application.properties=src/main/resources/application.properties \
  -n dashboard-app
```

---

## Troubleshooting

### Pod Not Starting

```bash
# Check pod events
kubectl describe pod -l app=dashboard-app -n dashboard-app

# Check pod logs
kubectl logs -l app=dashboard-app -n dashboard-app --previous
```

**Common causes**:
- `ImagePullBackOff`: Image URI incorrect or ECR permissions missing
- `CrashLoopBackOff`: Application startup failure – check logs
- `OOMKilled`: Increase memory limits in `deployment.yaml`

### Health Probe Failures

The application exposes `GET /api/health` which returns `{"status":"ok"}`.

```bash
# Port-forward to test locally
kubectl port-forward svc/dashboard-app-service 8080:80 -n dashboard-app

# Test health endpoint
curl http://localhost:8080/api/health
```

If probes fail:
- Increase `initialDelaySeconds` in `deployment.yaml` (JVM startup can be slow)
- Check application logs for startup errors

### Ingress Not Accessible

```bash
# Check ingress status
kubectl describe ingress dashboard-app-ingress -n dashboard-app

# Verify AWS Load Balancer Controller is running
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

**Common causes**:
- AWS Load Balancer Controller not installed
- Missing IAM permissions for ALB creation
- Security group rules blocking traffic

### ECR Authentication Issues

```bash
# Re-authenticate with ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin \
  123456789012.dkr.ecr.us-east-1.amazonaws.com
```

### kubectl Context Issues

```bash
# List available contexts
kubectl config get-contexts

# Switch context
kubectl config use-context <context-name>

# Re-configure for EKS
aws eks update-kubeconfig --region us-east-1 --name my-cluster
```

---

## Security Considerations

1. **Non-root container**: The application runs as UID 1000 (`appuser`) – never as root.
2. **Read-only filesystem**: Consider enabling `readOnlyRootFilesystem: true` if the app does not write to disk.
3. **Dropped capabilities**: All Linux capabilities are dropped (`capabilities.drop: [ALL]`).
4. **Secrets management**: Use Kubernetes Secrets or AWS Secrets Manager for sensitive values – never hardcode credentials.
5. **Image scanning**: Enable ECR image scanning to detect vulnerabilities.
6. **Network policies**: Implement Kubernetes NetworkPolicies to restrict pod-to-pod communication.
7. **RBAC**: Apply least-privilege RBAC roles for service accounts.
8. **TLS**: The ingress is configured to redirect HTTP to HTTPS (port 443). Ensure an ACM certificate is attached to the ALB.

---

## Java-Specific Notes

### JVM Memory Configuration

The container is configured with container-aware JVM flags:

```
-XX:+UseContainerSupport       # Respect container memory limits
-XX:MaxRAMPercentage=75.0      # Use 75% of container memory as heap max
-Xms256m                       # Initial heap size
-Xmx512m                       # Maximum heap size
-XX:+UnlockExperimentalVMOptions
```

With a 1Gi memory limit, the JVM will use up to ~768Mi for heap.

### Spring Boot Profile

The `SPRING_PROFILES_ACTIVE=docker` environment variable activates the `docker` Spring profile. Create `src/main/resources/application-docker.properties` to add Docker-specific overrides.

### Graceful Shutdown

Spring Boot 3.x supports graceful shutdown. Add to `application.properties`:

```properties
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
```

The Kubernetes `terminationGracePeriodSeconds: 30` is aligned with this setting.

### Startup Time

Amazon Corretto 17 JVM startup typically takes 10–30 seconds. The startup probe allows up to 120 seconds (`failureThreshold: 12` × `periodSeconds: 10`) before marking the pod as failed.

### Logging

For structured logging in Kubernetes (compatible with CloudWatch Logs Insights):

Add to `pom.xml`:
```xml
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
    <version>7.4</version>
</dependency>
```

Configure `logback-spring.xml` to output JSON format for better log aggregation.
