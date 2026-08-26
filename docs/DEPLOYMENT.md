# dashboard-app — Deployment Guide

## Overview

**Application**: dashboard-app  
**Framework**: Spring Boot 3.2.5 (Java 17) + Angular (Node 18) frontend  
**Build Tool**: Maven  
**Package Type**: JAR  
**Target Platform**: AWS EKS (Elastic Kubernetes Service)  
**Runtime Base Image**: `mcr.microsoft.com/openjdk/jdk:17-ubuntu` (JRE via `openjdk17-jre-headless` on `nginx:alpine`)  
**Application Port**: 8080 (Spring Boot API), 80 (nginx frontend)  
**Health Endpoint**: `/health` (nginx), `/api/health` (Spring Boot)

---

## Prerequisites

### Local Development
| Tool | Version | Purpose |
|------|---------|---------|
| Docker | 24.x+ | Build and run containers |
| Docker Compose | 2.x+ | Local multi-service orchestration |
| Java JDK | 17 | Local Spring Boot development |
| Maven | 3.9.x | Build tool |
| Node.js | 18.x | Frontend build |

### AWS EKS Deployment
| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | 2.x | AWS authentication and ECR |
| kubectl | 1.28+ | Kubernetes cluster management |
| eksctl | 0.170+ | EKS cluster provisioning (optional) |

### IAM Permissions Required
```
ecr:GetAuthorizationToken
ecr:BatchCheckLayerAvailability
ecr:GetDownloadUrlForLayer
ecr:BatchGetImage
ecr:PutImage
ecr:InitiateLayerUpload
ecr:UploadLayerPart
ecr:CompleteLayerUpload
ecr:CreateRepository
ecr:DescribeRepositories
eks:DescribeCluster
eks:ListClusters
```

---

## Project Structure

```
JAVACSSMONOrg/
├── Dockerfile                    # Multi-stage build (Angular + CSS + Java → nginx:alpine)
├── docker-compose.yml            # Local development compose file
├── .dockerignore                 # Docker build context exclusions
├── nginx.conf                    # nginx reverse-proxy configuration
├── docker-entrypoint.sh          # Container startup script
├── pom.xml                       # Maven build descriptor
├── package.json                  # Node.js / Angular dependencies
├── src/
│   └── main/
│       ├── java/com/trianz/dashboard/
│       │   ├── DashboardApplication.java
│       │   ├── controller/HealthController.java
│       │   └── service/HealthService.java
│       └── resources/
│           └── application.properties
├── assets/styles/                # CSS / SCSS assets
├── frontend/                     # Angular components
├── styles/                       # LESS source files
├── kubernetes/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── scripts/
│   ├── build-push.sh             # Linux/macOS build & push
│   ├── build-push.bat            # Windows build & push
│   ├── deploy-image.sh           # Linux/macOS EKS deploy
│   └── deploy-image.bat          # Windows EKS deploy
└── docs/
    └── DEPLOYMENT.md             # This file
```

---

## Local Development Setup

### 1. Build and Run with Docker Compose

```bash
# Build and start the application
docker-compose up --build

# Run in detached mode
docker-compose up --build -d

# View logs
docker-compose logs -f dashboard-app

# Stop the application
docker-compose down
```

### 2. Access the Application

| Endpoint | URL |
|----------|-----|
| Frontend (nginx) | http://localhost:80 |
| Spring Boot API | http://localhost:8080 |
| Health Check | http://localhost/health |
| API Health | http://localhost/api/health |

### 3. Local Maven Build (without Docker)

```bash
# Build the Spring Boot JAR
mvn clean package -DskipTests

# Run the application
java -jar target/dashboard-app-1.0.0.jar
```

---

## Docker Image Build

### Multi-Stage Build Overview

The Dockerfile uses 5 build stages:

1. **angular-build** — Node 18: installs Angular CLI, compiles Angular app to `dist/`
2. **scss-less-build** — Node 18: compiles SCSS/LESS sources to plain CSS
3. **css-build** — Node 18: PurgeCSS removes unused rules, PostCSS/cssnano minifies, Critters inlines critical CSS
4. **java-build** — `maven:3.9.4-eclipse-temurin-17`: compiles Spring Boot JAR
5. **production** — `nginx:alpine` + `openjdk17-jre-headless`: serves Angular dist via nginx, runs Spring Boot JAR

### Build the Image Manually

```bash
# Build with default tag
docker build -t dashboard-app:latest .

# Build with specific tag
docker build -t dashboard-app:1.0.0 .
```

---

## Build and Push to Registry

### Linux / macOS

```bash
# Make script executable
chmod +x scripts/build-push.sh

# Run the script (prompts for registry details)
./scripts/build-push.sh
```

### Windows

```cmd
scripts\build-push.bat
```

The script will prompt for:
1. **Image tag** (default: `latest`)
2. **Registry type**: `1` for AWS ECR, `2` for Docker Hub
3. **Registry credentials** based on selection

#### AWS ECR Example
```
Enter image tag [latest]: 1.0.0
Select container registry:
  1. AWS ECR
  2. Docker Hub
Enter choice [1]: 1
Enter AWS Region [us-east-1]: us-east-1
Enter AWS Account ID: 123456789012
```

#### Docker Hub Example
```
Enter image tag [latest]: 1.0.0
Select container registry:
  1. AWS ECR
  2. Docker Hub
Enter choice [1]: 2
Enter Docker Hub username: myusername
Enter Docker Hub password/token: ****
```

---

## AWS EKS Deployment

### Prerequisites

#### 1. Configure AWS CLI
```bash
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region, Output format
```

#### 2. Verify EKS Cluster Access
```bash
aws eks list-clusters --region us-east-1
aws eks describe-cluster --name <cluster-name> --region us-east-1
```

#### 3. Install AWS Load Balancer Controller (for Ingress)
```bash
# Add the EKS chart repository
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=<cluster-name> \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### Deploy to EKS

#### Linux / macOS
```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

#### Windows
```cmd
scripts\deploy-image.bat
```

The script will prompt for:
1. **AWS Region** (default: `us-east-1`)
2. **EKS Cluster Name**
3. **Docker Image URI** (full path with tag)

#### Example
```
Enter AWS Region [us-east-1]: us-east-1
Enter EKS Cluster Name: my-eks-cluster
Enter Docker Image URI: 123456789012.dkr.ecr.us-east-1.amazonaws.com/dashboard-app:1.0.0
```

### Manual Kubernetes Deployment

```bash
# Configure kubectl
aws eks update-kubeconfig --region us-east-1 --name <cluster-name>

# Update image URI in deployment manifest
sed -i 's|{{IMAGE_URI}}|<your-image-uri>|g' kubernetes/deployment.yaml

# Apply manifests in order
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml

# Wait for rollout
kubectl rollout status deployment/dashboard-app -n dashboard-app

# Verify resources
kubectl get pods,svc,ingress -n dashboard-app
```

---

## Kubernetes Manifest Reference

### namespace.yaml
Creates the `dashboard-app` namespace to isolate all application resources.

### deployment.yaml
- **Replicas**: 2 (high availability)
- **Image**: `{{IMAGE_URI}}` (replaced by deploy script)
- **Ports**: 80 (nginx), 8080 (Spring Boot)
- **Resources**:
  - Requests: `cpu: 250m`, `memory: 512Mi`
  - Limits: `cpu: 500m`, `memory: 1Gi`
- **Liveness Probe**: `GET /health` on port 80 (initial delay: 60s)
- **Readiness Probe**: `GET /health` on port 80 (initial delay: 30s)
- **JVM Options**: `-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`

### service.yaml
- **Type**: ClusterIP
- **Ports**: 80 → 80 (nginx), 8080 → 8080 (Spring Boot)

### ingress.yaml
- **Class**: AWS ALB (Application Load Balancer)
- **Scheme**: internet-facing
- **Health Check Path**: `/health`
- **Host**: `dashboard-app.example.com` (update to your domain)

---

## Configuration Management

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SPRING_PROFILES_ACTIVE` | `docker` | Active Spring profile |
| `SPRING_APPLICATION_NAME` | `dashboard-app` | Application name |
| `SERVER_PORT` | `8080` | Spring Boot server port |
| `TZ` | `UTC` | Container timezone |
| `JAVA_OPTS` | `-Xmx512m -Xms256m ...` | JVM options |

### Updating Configuration via ConfigMap (Recommended for EKS)

```bash
# Create a ConfigMap for application properties
kubectl create configmap dashboard-app-config \
  --from-literal=SPRING_PROFILES_ACTIVE=production \
  --from-literal=TZ=UTC \
  -n dashboard-app

# Reference in deployment.yaml under envFrom:
# envFrom:
#   - configMapRef:
#       name: dashboard-app-config
```

### Secrets Management

```bash
# Create a Secret for sensitive values
kubectl create secret generic dashboard-app-secrets \
  --from-literal=DB_PASSWORD=<password> \
  -n dashboard-app
```

---

## Scaling and Management

### Horizontal Pod Autoscaling

```bash
# Enable HPA
kubectl autoscale deployment dashboard-app \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n dashboard-app

# Check HPA status
kubectl get hpa -n dashboard-app
```

### Rolling Updates

```bash
# Update image
kubectl set image deployment/dashboard-app \
  dashboard-app=<new-image-uri> \
  -n dashboard-app

# Monitor rollout
kubectl rollout status deployment/dashboard-app -n dashboard-app
```

### Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/dashboard-app -n dashboard-app

# Rollback to specific revision
kubectl rollout history deployment/dashboard-app -n dashboard-app
kubectl rollout undo deployment/dashboard-app --to-revision=2 -n dashboard-app
```

---

## Troubleshooting

### Pod Issues

```bash
# List pods
kubectl get pods -n dashboard-app

# Describe a pod
kubectl describe pod <pod-name> -n dashboard-app

# View pod logs
kubectl logs <pod-name> -n dashboard-app
kubectl logs <pod-name> -n dashboard-app --previous   # crashed pod

# Stream logs
kubectl logs -f -l app=dashboard-app -n dashboard-app
```

### Common Issues

#### Pods in CrashLoopBackOff
```bash
kubectl logs <pod-name> -n dashboard-app --previous
# Check: JVM OOM, missing env vars, port conflicts
```

#### ImagePullBackOff
```bash
kubectl describe pod <pod-name> -n dashboard-app
# Check: ECR permissions, image URI correctness, imagePullSecrets
```

#### Ingress Not Getting ALB Hostname
```bash
kubectl describe ingress dashboard-app-ingress -n dashboard-app
# Check: AWS Load Balancer Controller installed, IAM permissions, subnet tags
```

#### Spring Boot Not Starting
```bash
# Check if nginx is running but Spring Boot failed
kubectl exec -it <pod-name> -n dashboard-app -- ps aux
kubectl exec -it <pod-name> -n dashboard-app -- cat /proc/1/fd/1
```

### Service Connectivity

```bash
# Port-forward for local testing
kubectl port-forward svc/dashboard-app-service 8080:8080 -n dashboard-app
kubectl port-forward svc/dashboard-app-service 8081:80 -n dashboard-app

# Test health endpoint
curl http://localhost:8081/health
curl http://localhost:8080/api/health
```

---

## Security Considerations

1. **Non-root user**: The container creates `appuser:appgroup` for running the application
2. **Read-only filesystem**: Consider adding `readOnlyRootFilesystem: true` to the security context
3. **Network Policies**: Restrict pod-to-pod communication using Kubernetes NetworkPolicy
4. **Secrets**: Never store secrets in environment variables directly; use AWS Secrets Manager or Kubernetes Secrets
5. **Image scanning**: Enable ECR image scanning on push for vulnerability detection
6. **RBAC**: Apply least-privilege IAM roles for EKS node groups
7. **TLS**: Configure HTTPS on the ALB using ACM certificates:
   ```yaml
   alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
   alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123456789012:certificate/xxx
   alb.ingress.kubernetes.io/ssl-redirect: '443'
   ```

---

## Java-Specific Notes

### JVM Container Optimizations
The following JVM flags are set via `JAVA_OPTS`:
- `-XX:+UseContainerSupport` — enables JVM container awareness (reads cgroup limits)
- `-XX:MaxRAMPercentage=75.0` — limits heap to 75% of container memory
- `-Xmx512m -Xms256m` — explicit heap bounds
- `-XX:+UnlockExperimentalVMOptions` — enables experimental container features

### Spring Boot Profile
The `docker` profile is activated via `SPRING_PROFILES_ACTIVE=docker`. Create `application-docker.properties` or `application-docker.yml` for Docker-specific overrides.

### Graceful Shutdown
Spring Boot 3.x supports graceful shutdown. Add to `application.properties`:
```properties
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=30s
```

### Actuator (Optional Enhancement)
To add Spring Boot Actuator health endpoints, add to `pom.xml`:
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
```
Then update Kubernetes probes to use `/actuator/health`.

---

## Quick Reference

```bash
# Build image
docker build -t dashboard-app:latest .

# Run locally
docker-compose up --build

# Build and push (interactive)
./scripts/build-push.sh

# Deploy to EKS (interactive)
./scripts/deploy-image.sh

# Check deployment status
kubectl get pods,svc,ingress -n dashboard-app

# View logs
kubectl logs -f -l app=dashboard-app -n dashboard-app

# Rollback
kubectl rollout undo deployment/dashboard-app -n dashboard-app
```
