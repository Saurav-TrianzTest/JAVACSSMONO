# Deployment Guide — dashboard-app on Azure AKS

## Overview

This guide covers building, pushing, and deploying the **dashboard-app** Spring Boot application to **Azure Kubernetes Service (AKS)**. The application is a Java 17 Spring Boot 3.2.5 web service packaged as a JAR and containerised using a multi-stage Docker build.

---

## Prerequisites

### Local Development
- **Docker Desktop** 24.x or later
- **Java 17** (for local development only)
- **Maven 3.9.x** (for local development only)
- **Node.js 18.x** (for CSS/frontend build pipeline)

### Azure AKS Deployment
- **Azure CLI** (`az`) 2.50+
- **kubectl** 1.28+
- **Azure Subscription** with permissions to create/manage AKS and ACR resources
- **Azure Container Registry (ACR)** or Docker Hub account

---

## Project Structure

```
JavaCSSmonoAKS/
├── Dockerfile                  # Multi-stage build (Angular + CSS + Java)
├── docker-compose.yml          # Local development compose (app only)
├── .dockerignore               # Excludes build artifacts and wrapper files
├── pom.xml                     # Maven build descriptor (Spring Boot 3.2.5, Java 17)
├── src/
│   └── main/
│       ├── java/com/trianz/dashboard/
│       │   ├── DashboardApplication.java
│       │   ├── controller/HealthController.java   # GET /api/health
│       │   └── service/HealthService.java
│       └── resources/
│           └── application.properties             # server.port=8080
├── kubernetes/
│   ├── namespace.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
├── scripts/
│   ├── build-push.sh           # Linux/macOS build & push
│   ├── build-push.bat          # Windows build & push
│   ├── deploy-image.sh         # Linux/macOS AKS deploy
│   └── deploy-image.bat        # Windows AKS deploy
└── docs/
    └── DEPLOYMENT.md           # This file
```

---

## Technology Stack

| Component        | Technology                        |
|------------------|-----------------------------------|
| Language         | Java 17                           |
| Framework        | Spring Boot 3.2.5                 |
| Build Tool       | Maven 3.9.x                       |
| Package Type     | JAR (executable)                  |
| Application Port | 8080                              |
| Health Endpoint  | `GET /api/health`                 |
| Builder Image    | `maven:3.9.4-eclipse-temurin-17`  |
| Runtime Image    | `eclipse-temurin:17-jdk`          |
| Target Platform  | Azure AKS                         |

---

## Local Development Setup

### 1. Run with Docker Compose

```bash
# Build and start the application container
docker compose up --build

# Run in background
docker compose up --build -d

# View logs
docker compose logs -f dashboard-app

# Stop
docker compose down
```

The application will be available at: `http://localhost:8080`  
Health check: `http://localhost:8080/api/health`

### 2. Run Locally with Maven

```bash
# Build
mvn clean package -DskipTests

# Run
java -jar target/dashboard-app-1.0.0.jar
```

---

## Build and Push Docker Image

### Linux / macOS

```bash
# Make script executable (first time only)
chmod +x scripts/build-push.sh

# Run from repository root
./scripts/build-push.sh
```

### Windows

```cmd
REM Run from repository root
scripts\build-push.bat
```

The script will prompt you to:
1. Enter an image tag (defaults to `latest`)
2. Select registry type: **Azure ACR** or **Docker Hub**
3. Provide registry credentials

**Example ACR flow:**
```
Enter image tag (press Enter for 'latest'): v1.0.0
Select container registry:
  1. Azure Container Registry (ACR)
  2. Docker Hub
Enter choice [1-2]: 1
Enter ACR name (e.g. myregistry): mycompanyacr
```

The final image will be tagged as: `mycompanyacr.azurecr.io/dashboard-app:v1.0.0`

---

## Azure AKS Deployment

### Step 1: Azure Prerequisites

```bash
# Login to Azure
az login

# Set subscription (if multiple)
az account set --subscription "<SUBSCRIPTION_ID>"

# Verify ACR exists (or create one)
az acr show --name <ACR_NAME> --resource-group <RESOURCE_GROUP>

# Create ACR if needed
az acr create --resource-group <RESOURCE_GROUP> --name <ACR_NAME> --sku Basic
```

### Step 2: AKS Cluster Setup

```bash
# Create AKS cluster (if not existing)
az aks create \
  --resource-group <RESOURCE_GROUP> \
  --name <CLUSTER_NAME> \
  --node-count 2 \
  --node-vm-size Standard_DS2_v2 \
  --attach-acr <ACR_NAME> \
  --generate-ssh-keys

# Configure kubectl
az aks get-credentials --resource-group <RESOURCE_GROUP> --name <CLUSTER_NAME>

# Verify connectivity
kubectl cluster-info
kubectl get nodes
```

### Step 3: Deploy to AKS

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
- Azure Resource Group name
- AKS Cluster name
- Full Docker image URI (e.g. `mycompanyacr.azurecr.io/dashboard-app:v1.0.0`)

### Step 4: Verify Deployment

```bash
# Check all resources in namespace
kubectl get pods,svc,ingress -n dashboard-app

# Check pod logs
kubectl logs -l app=dashboard-app -n dashboard-app

# Describe deployment
kubectl describe deployment dashboard-app -n dashboard-app

# Test health endpoint (port-forward for quick test)
kubectl port-forward svc/dashboard-app-service 8080:80 -n dashboard-app
curl http://localhost:8080/api/health
```

---

## Kubernetes Manifest Descriptions

### namespace.yaml
Creates the `dashboard-app` namespace to isolate all application resources.

### deployment.yaml
- **Replicas**: 2 (high availability)
- **Image**: `{{IMAGE_URI}}` — replaced by deploy script
- **Port**: 8080
- **Resources**: requests `250m CPU / 512Mi RAM`, limits `500m CPU / 1Gi RAM`
- **Liveness Probe**: `GET /api/health` — starts after 45s, every 15s
- **Readiness Probe**: `GET /api/health` — starts after 30s, every 10s
- **JVM Options**: Container-aware heap sizing (`-XX:MaxRAMPercentage=75.0`)

### service.yaml
- **Type**: ClusterIP (internal cluster access)
- **Port mapping**: 80 → 8080

### ingress.yaml
- **Class**: `azure/application-gateway` (Azure AGIC)
- **Host**: `dashboard-app.example.com` (update to your actual domain)
- **Path**: `/` (all traffic routed to service)

---

## Configuration Management

### Environment Variables

| Variable                | Default   | Description                          |
|-------------------------|-----------|--------------------------------------|
| `SPRING_PROFILES_ACTIVE`| `docker`  | Active Spring profile                |
| `SERVER_PORT`           | `8080`    | Application HTTP port                |
| `TZ`                    | `UTC`     | Container timezone                   |
| `JAVA_OPTS`             | See below | JVM tuning flags                     |

**Default JAVA_OPTS:**
```
-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions -Xms256m -Xmx512m
```

### Updating Ingress Host

Edit `kubernetes/ingress.yaml` and replace `dashboard-app.example.com` with your actual domain:

```yaml
spec:
  rules:
    - host: your-actual-domain.com
```

---

## AKS Scaling and Management

### Manual Scaling

```bash
# Scale to 3 replicas
kubectl scale deployment dashboard-app --replicas=3 -n dashboard-app
```

### Horizontal Pod Autoscaler (HPA)

```bash
kubectl autoscale deployment dashboard-app \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n dashboard-app

kubectl get hpa -n dashboard-app
```

### Rolling Update

```bash
# Update image
kubectl set image deployment/dashboard-app \
  dashboard-app=mycompanyacr.azurecr.io/dashboard-app:v2.0.0 \
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

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -n dashboard-app

# Describe failing pod
kubectl describe pod <POD_NAME> -n dashboard-app

# Check pod logs
kubectl logs <POD_NAME> -n dashboard-app
kubectl logs <POD_NAME> -n dashboard-app --previous  # crashed pod logs
```

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| `ImagePullBackOff` | ACR auth failure | Ensure AKS has ACR pull permission: `az aks update --attach-acr <ACR_NAME>` |
| `CrashLoopBackOff` | App startup failure | Check logs: `kubectl logs <POD> -n dashboard-app` |
| `OOMKilled` | Insufficient memory | Increase memory limits in `deployment.yaml` |
| `Pending` pods | Insufficient node resources | Scale node pool or reduce resource requests |
| Health probe failing | App not ready | Increase `initialDelaySeconds` in deployment probes |

### Service Not Accessible

```bash
# Check service endpoints
kubectl get endpoints dashboard-app-service -n dashboard-app

# Port-forward for local testing
kubectl port-forward svc/dashboard-app-service 8080:80 -n dashboard-app
```

### Ingress Not Working

```bash
# Check AGIC is installed
kubectl get pods -n kube-system | grep ingress

# Check ingress status
kubectl describe ingress dashboard-app-ingress -n dashboard-app

# Check ingress IP
kubectl get ingress -n dashboard-app
```

---

## Security Considerations

1. **Non-root container**: The application runs as `appuser` (non-root) inside the container.
2. **Read-only config volume**: Config volume is mounted as read-only (`:ro`).
3. **ACR Workload Identity**: Use AKS Workload Identity for credential-free ACR pulls in production.
4. **Secrets management**: Use Azure Key Vault with the Secrets Store CSI Driver for sensitive configuration.
5. **Network policies**: Apply Kubernetes NetworkPolicy to restrict pod-to-pod communication.
6. **Image scanning**: Enable ACR vulnerability scanning for pushed images.

---

## Java-Specific Notes

- **Spring Boot 3.2.5** requires Java 17 minimum — the `eclipse-temurin:17-jdk` runtime image satisfies this.
- **Container-aware JVM**: `-XX:+UseContainerSupport` ensures the JVM respects container memory limits rather than host memory.
- **Heap sizing**: `-XX:MaxRAMPercentage=75.0` allocates 75% of container memory to the JVM heap automatically.
- **Graceful shutdown**: `terminationGracePeriodSeconds: 30` allows in-flight requests to complete before pod termination.
- **Health endpoint**: The custom `/api/health` endpoint (from `HealthController`) is used for both liveness and readiness probes.
- **Spring profile**: `SPRING_PROFILES_ACTIVE=docker` activates the Docker-specific Spring profile for environment-appropriate configuration.
