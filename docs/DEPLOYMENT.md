# dashboard-app Deployment Guide (AWS EKS)

## Application summary
- Spring Boot 3.2.5, Java 17, Maven, executable JAR (`dashboard-app-1.0.0.jar`)
- Port: 8080 (`server.port`)
- Health endpoint: `/api/health` (custom controller; Spring Boot Actuator is not a dependency)
- No external services (database, cache, queue) are required.

> The previous nginx/CSS-optimisation Dockerfile was preserved as `Dockerfile.frontend`.

## Prerequisites
Docker, AWS CLI v2 (configured with credentials), kubectl, eksctl (optional), an EKS cluster with the AWS Load Balancer Controller installed, and IAM permissions for ECR and `eks:DescribeCluster`.

## Local run
```
docker compose up --build
curl http://localhost:8080/api/health
```

## Build and push
Run from the repository root:
```
./scripts/build-push.sh      # Linux/macOS
scripts\build-push.bat       # Windows
```
Choose AWS ECR or Docker Hub; the ECR repository is created automatically if missing. Empty tags default to `latest`.

## Deploy to EKS
```
./scripts/deploy-image.sh    # or scripts\deploy-image.bat
```
The script prompts for region, cluster name, image URI and `SPRING_PROFILES_ACTIVE`, substitutes `{{IMAGE_URI}}` and `{{SPRING_PROFILES_ACTIVE}}` in a temporary copy of the manifests, configures kubeconfig, and applies: namespace -> deployment -> service -> ingress. It then waits for rollout and prints resources.

Manifests (`kubernetes/`): namespace `dashboard-app`; Deployment with 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP probes on `/api/health`; ClusterIP Service 80 -> 8080; ALB Ingress (host `dashboard-app.example.com` - edit as needed, and add ACM/HTTPS annotations for TLS).

## Operations
- Scale: `kubectl scale deployment/dashboard-app -n dashboard-app --replicas=4`; or create an HPA (`kubectl autoscale deployment dashboard-app -n dashboard-app --cpu-percent=70 --min=2 --max=6`; requires metrics-server).
- Update: re-run deploy with a new image tag (rolling update, maxUnavailable 0).
- Rollback: `kubectl rollout undo deployment/dashboard-app -n dashboard-app`

## Troubleshooting
- Pods not Ready: `kubectl describe pod`, `kubectl logs -n dashboard-app deploy/dashboard-app`; JVM start-up may need larger `initialDelaySeconds`.
- ImagePullBackOff: verify the image URI and that node IAM role has `AmazonEC2ContainerRegistryReadOnly`.
- OOMKilled: raise memory limit; heap is 75% of container memory (`MaxRAMPercentage`).
- Ingress has no address: confirm AWS Load Balancer Controller is running and subnets are tagged; `kubectl describe ingress -n dashboard-app`.
- Service unreachable: `kubectl get endpoints -n dashboard-app`.

## Configuration and security
- Env vars: `SPRING_PROFILES_ACTIVE`, `SERVER_PORT`, `JAVA_OPTS`, `TZ`. Any Spring property can be supplied as an env var.
- Container runs as a non-root user; use Secrets (not plain env) for credentials; restrict ECR access with least-privilege IAM; enable TLS on the ALB.
