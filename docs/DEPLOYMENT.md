# Deployment Guide — dashboard-app on Azure AKS

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Local Development with Docker Compose](#local-development-with-docker-compose)
5. [Build and Push Docker Image](#build-and-push-docker-image)
6. [Azure AKS Deployment](#azure-aks-deployment)
7. [Kubernetes Manifest Reference](#kubernetes-manifest-reference)
8. [Configuration Management](#configuration-management)
9. [Scaling and Management](#scaling-and-management)
10. [Troubleshooting](#troubleshooting)
11. [Security Considerations](#security-considerations)

---

## Overview

**Application**: dashboard-app  
**Framework**: Spring Boot 3.2.5  
**Java Version**: 17  
**Build Tool**: Maven  
**Package Type**: JAR  
**Runtime Base Image**: amazoncorretto:17  
**Target Platform**: Azure Kubernetes Service (AKS)  
**Application Port**: 8080  
**Health Endpoint**: `/api/health`

---

## Prerequisites

### Local Development
| Tool | Version | Purpose |
|------|---------|---------|
| Java JDK | 17+ | Build and run locally |
| Maven | 3.9+ | Build tool |
| Docker | 24+ | Container build and run |
| Docker Compose | 2.x | Local multi-container orchestration |

### Azure AKS Deployment
| Tool | Version | Purpose |
|------|---------|---------|
| Azure CLI (`az`) | 2.50+ | Azure resource management |
| kubectl | 1.27+ | Kubernetes cluster management |
| Docker | 24+ | Image build and push |
| Azure Subscription | — | AKS cluster and ACR hosting |

### Install Azure CLI
```bash
# macOS
brew install azure-cli

# Ubuntu/Debian
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Windows (PowerShell)
winget install Microsoft.AzureCLI
```

### Install kubectl
```bash
# macOS
brew install kubectl

# Ubuntu/Debian
sudo az aks install-cli

# Windows (PowerShell)
winget install Kubernetes.kubectl
```

---

## Project Structure

```
AZURE-AKS2CMP/
├── Dockerfile                  # Multi-stage build (builder + amazoncorretto:17 runtime)
├── .dockerignore               # Excludes wrapper files, target/, .git/, etc.
├── docker-compose.yml          # Local development (application only)
├── pom.xml                     # Maven build descriptor
├── src/
│   └── main/
│       ├── java/com/trianz/dashboard/
│       │   ├── DashboardApplication.java
│       │   ├── controller/HealthController.java
│       │   └── service/HealthService.java
│       └── resources/
│           └── application.properties
├── kubernetes/
│   ├── namespace.yaml          # Kubernetes namespace
│   ├── deployment.yaml         # Deployment (2 replicas, health probes)
│   ├── service.yaml            # ClusterIP service (port 80 → 8080)
│   └── ingress.yaml            # Azure Application Gateway Ingress
├── scripts/
│   ├── build-push.sh           # Linux/macOS: build & push to ACR or Docker Hub
│   ├── build-push.bat          # Windows: build & push to ACR or Docker Hub
│   ├── deploy-image.sh         # Linux/macOS: deploy to AKS
│   └── deploy-image.bat        # Windows: deploy to AKS
└── docs/
    └── DEPLOYMENT.md           # This file
```

---

## Local Development with Docker Compose

### 1. Build and Start the Application

```bash
# From the project root
docker compose up --build
```

The application will be available at: **http://localhost:8080**

### 2. Verify the Application

```bash
# Health check
curl http://localhost:8080/api/health
# Expected: {"status":"ok"}
```

### 3. Stop the Application

```bash
docker compose down
```

### 4. Environment Variable Overrides

Create a `.env` file in the project root to override defaults:

```env
SPRING_PROFILES_ACTIVE=local
SERVER_PORT=8080
# DATABASE_URL=jdbc:postgresql://localhost:5432/dashboard
# DATABASE_USERNAME=dashboard_user
# DATABASE_PASSWORD=secret
```

---

## Build and Push Docker Image

### Linux / macOS

```bash
chmod +x scripts/build-push.sh
bash scripts/build-push.sh
```

### Windows

```cmd
scripts\build-push.bat
```

### Script Prompts

The script will interactively ask for:

1. **Image tag** — defaults to `latest`
2. **Registry type**:
   - `1` → Azure Container Registry (ACR): prompts for ACR name, then runs `az acr login`
   - `2` → Docker Hub: prompts for username and password/token

### Manual Build (ACR example)

```bash
# Login to ACR
az acr login --name <your-acr-name>

# Build
docker build -t <your-acr-name>.azurecr.io/dashboard-app:latest .

# Push
docker push <your-acr-name>.azurecr.io/dashboard-app:latest
```

---

## Azure AKS Deployment

### Step 1: Create Azure Resources (if not already created)

```bash
# Login to Azure
az login

# Set subscription
az account set --subscription "<your-subscription-id>"

# Create resource group
az group create --name dashboard-rg --location eastus

# Create ACR
az acr create --resource-group dashboard-rg \
              --name dashboardacr \
              --sku Basic

# Create AKS cluster with ACR integration
az aks create \
  --resource-group dashboard-rg \
  --name dashboard-aks \
  --node-count 2 \
  --node-vm-size Standard_DS2_v2 \
  --enable-addons ingress-appgw \
  --appgw-name dashboard-appgw \
  --appgw-subnet-cidr "10.225.0.0/16" \
  --attach-acr dashboardacr \
  --generate-ssh-keys
```

### Step 2: Build and Push the Image

```bash
bash scripts/build-push.sh
# Select option 1 (ACR), enter: dashboardacr
# Enter tag: v1.0.0
```

### Step 3: Deploy to AKS

#### Linux / macOS
```bash
chmod +x scripts/deploy-image.sh
bash scripts/deploy-image.sh
```

#### Windows
```cmd
scripts\deploy-image.bat
```

The script will prompt for:
- **Azure Resource Group**: e.g., `dashboard-rg`
- **AKS Cluster name**: e.g., `dashboard-aks`
- **Docker image URI**: e.g., `dashboardacr.azurecr.io/dashboard-app:v1.0.0`

### Step 4: Verify Deployment

```bash
# Check pods
kubectl get pods -n dashboard-app

# Check services
kubectl get svc -n dashboard-app

# Check ingress
kubectl get ingress -n dashboard-app

# View pod logs
kubectl logs -l app=dashboard-app -n dashboard-app --tail=100

# Test health endpoint (port-forward for quick test)
kubectl port-forward svc/dashboard-app-service 8080:80 -n dashboard-app
curl http://localhost:8080/api/health
```

---

## Kubernetes Manifest Reference

### namespace.yaml
Creates the `dashboard-app` namespace to isolate all application resources.

### deployment.yaml
| Field | Value |
|-------|-------|
| Replicas | 2 |
| Image | `{{IMAGE_URI}}` (replaced by deploy script) |
| Container Port | 8080 |
| CPU Request | 250m |
| CPU Limit | 500m |
| Memory Request | 512Mi |
| Memory Limit | 1Gi |
| Liveness Probe | `GET /api/health` (initial delay: 60s, period: 30s) |
| Readiness Probe | `GET /api/health` (initial delay: 30s, period: 15s) |

### service.yaml
| Field | Value |
|-------|-------|
| Type | ClusterIP |
| Port | 80 |
| Target Port | 8080 |

### ingress.yaml
| Field | Value |
|-------|-------|
| Class | `azure/application-gateway` |
| Host | `dashboard-app.example.com` |
| Path | `/` (Prefix) |
| Backend | `dashboard-app-service:80` |

> **Note**: Update the `host` field in `kubernetes/ingress.yaml` to your actual domain before deploying.

---

## Configuration Management

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SPRING_PROFILES_ACTIVE` | `docker` | Active Spring profile |
| `SPRING_APPLICATION_NAME` | `dashboard-app` | Application name |
| `SERVER_PORT` | `8080` | HTTP server port |
| `JAVA_OPTS` | JVM flags | JVM tuning options |

### JVM Tuning

The default `JAVA_OPTS` in the Deployment:
```
-XX:+UseContainerSupport
-XX:MaxRAMPercentage=75.0
-XX:+UnlockExperimentalVMOptions
-Xms256m
-Xmx512m
-Dfile.encoding=UTF-8
-Duser.timezone=UTC
```

Adjust `MaxRAMPercentage` and heap sizes based on your container memory limits.

### Using Kubernetes Secrets for Sensitive Values

```bash
# Create a secret for sensitive configuration
kubectl create secret generic dashboard-app-secrets \
  --from-literal=DATABASE_PASSWORD=mysecretpassword \
  -n dashboard-app
```

Reference in `deployment.yaml`:
```yaml
env:
  - name: DATABASE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: dashboard-app-secrets
        key: DATABASE_PASSWORD
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
kubectl autoscale deployment dashboard-app \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n dashboard-app

# Check HPA status
kubectl get hpa -n dashboard-app
```

### Rolling Update

```bash
# Update image
kubectl set image deployment/dashboard-app \
  dashboard-app=dashboardacr.azurecr.io/dashboard-app:v2.0.0 \
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
# Describe pod for events
kubectl describe pod -l app=dashboard-app -n dashboard-app

# Check pod logs
kubectl logs -l app=dashboard-app -n dashboard-app --previous
```

**Common causes:**
- Image pull failure → verify ACR credentials and image URI
- OOMKilled → increase memory limits in `deployment.yaml`
- CrashLoopBackOff → check application logs for startup errors

### Health Probe Failures

```bash
# Port-forward and test health endpoint manually
kubectl port-forward svc/dashboard-app-service 8080:80 -n dashboard-app
curl -v http://localhost:8080/api/health
```

**Common causes:**
- JVM startup time exceeds `initialDelaySeconds` → increase to 90s for slow starts
- Application error on startup → check logs

### Ingress Not Accessible

```bash
# Check ingress status
kubectl describe ingress dashboard-app-ingress -n dashboard-app

# Check Application Gateway health
az network application-gateway show \
  --resource-group dashboard-rg \
  --name dashboard-appgw \
  --query "operationalState"
```

**Common causes:**
- Application Gateway not provisioned → wait 5-10 minutes after AKS creation
- Incorrect host header → update `host` in `ingress.yaml`

### Image Pull Errors

```bash
# Verify ACR attachment to AKS
az aks check-acr --resource-group dashboard-rg \
                 --name dashboard-aks \
                 --acr dashboardacr.azurecr.io
```

### View All Resources

```bash
kubectl get all -n dashboard-app
```

---

## Security Considerations

1. **Non-root container**: The application runs as `appuser` (UID 1000) — never as root.
2. **Read-only filesystem**: Consider enabling `readOnlyRootFilesystem: true` if the app does not write to disk.
3. **Dropped capabilities**: All Linux capabilities are dropped (`capabilities.drop: [ALL]`).
4. **Secrets management**: Use Kubernetes Secrets or Azure Key Vault for sensitive values — never hardcode credentials.
5. **Network policies**: Apply Kubernetes NetworkPolicy to restrict pod-to-pod communication.
6. **Image scanning**: Enable ACR vulnerability scanning:
   ```bash
   az acr task create --registry dashboardacr \
     --name scan-on-push \
     --image dashboard-app:{{.Run.ID}} \
     --context /dev/null \
     --file /dev/null \
     --commit-trigger-enabled false \
     --base-image-trigger-enabled true
   ```
7. **RBAC**: Use Azure RBAC and Kubernetes RBAC to limit access to the cluster.
8. **TLS**: Configure TLS termination at the Application Gateway level using an SSL certificate.

---

*Generated for dashboard-app — Spring Boot 3.2.5 / Java 17 / Azure AKS*
