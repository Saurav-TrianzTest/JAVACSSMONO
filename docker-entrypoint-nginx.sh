#!/bin/sh
# =============================================================================
# docker-entrypoint-nginx.sh
# Rule cz-js-1014: Angular Runtime Environment Config Injection via
#                  AWS Secrets Manager / SSM Parameter Store
# Rule cz-css-1012: SSM Parameter Store nginx.conf Injection
#
# This entrypoint script is executed when the ECS Fargate container starts.
#
# Step 1 (cz-js-1014): Generates /usr/share/nginx/html/assets/env-config.js
# from environment variables injected by ECS Fargate via AWS Secrets Manager
# / SSM Parameter Store (secrets field in ecs/task-definition.json).
# Angular reads window.__ENV_CONFIG__ at runtime instead of using baked-in
# environment.ts values, enabling a single image to be promoted across dev,
# staging, and production without rebuilding the image.
#
# Step 2 (cz-css-1012): Writes the NGINX_CONF environment variable value
# (injected from AWS SSM Parameter Store via the ECS task definition `secrets`
# field) to the nginx configuration file before starting NGINX.
# This enables environment-specific nginx routing rules (dev, staging, prod)
# without rebuilding the container image.
#
# ECS Task Definition secrets field (ecs/task-definition.json):
#   Angular env config (cz-js-1014):
#     { "name": "API_BASE_URL",   "valueFrom": "arn:aws:secretsmanager:..." }
#     { "name": "FEATURE_FLAGS",  "valueFrom": "arn:aws:secretsmanager:..." }
#     { "name": "APP_ENV",        "valueFrom": "arn:aws:ssm:...:parameter/dashboard-app/<env>/app-env" }
#   nginx.conf (cz-css-1012):
#     { "name": "NGINX_CONF",     "valueFrom": "arn:aws:ssm:...:parameter/dashboard-app/<env>/nginx-conf" }
#
# SSM Parameter Store setup (one-time per environment):
#   aws ssm put-parameter \
#     --name "/dashboard-app/dev/nginx-conf" \
#     --type "String" \
#     --value "$(cat nginx/nginx.conf)" \
#     --region us-east-1
#
# Secrets Manager setup (one-time per environment):
#   aws secretsmanager create-secret \
#     --name "dashboard-app/dev/api-base-url" \
#     --secret-string "https://api.dev.example.com" \
#     --region us-east-1
# =============================================================================

set -e

ENV_CONFIG_PATH="/usr/share/nginx/html/assets/env-config.js"
NGINX_CONF_PATH="/etc/nginx/conf.d/default.conf"

echo "[entrypoint] Starting Angular runtime environment config injection (cz-js-1014)..."

# ---------------------------------------------------------------------------
# Step 1: Generate Angular runtime environment config (cz-js-1014)
#
# Writes window.__ENV_CONFIG__ to env-config.js so Angular can read
# environment-specific API endpoints and feature flags at runtime without
# baking them into the image. The values are injected by ECS Fargate from
# AWS Secrets Manager / SSM Parameter Store at task launch.
#
# Angular usage (in app.module.ts or environment service):
#   const config = (window as any).__ENV_CONFIG__ || {};
#   const apiBaseUrl = config.API_BASE_URL || 'http://localhost:8080';
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "$ENV_CONFIG_PATH")"

cat > "${ENV_CONFIG_PATH}" <<EOF
// =============================================================================
// Angular Runtime Environment Configuration
// Generated at container startup by docker-entrypoint-nginx.sh
// Rule cz-js-1014: Environment config injected via ECS Fargate Secrets Manager
// DO NOT EDIT — this file is auto-generated at runtime from ECS task secrets
// =============================================================================
(function(window) {
  window.__ENV_CONFIG__ = {
    API_BASE_URL:   "${API_BASE_URL:-http://localhost:8080}",
    ASSET_BASE_URL: "${ASSET_BASE_URL:-}",
    CDN_BASE_URL:   "${CDN_BASE_URL:-}",
    APP_ENV:        "${APP_ENV:-local}",
    FEATURE_FLAGS:  ${FEATURE_FLAGS:-\{\}}
  };
})(window);
EOF

echo "[entrypoint] Angular env-config.js written to ${ENV_CONFIG_PATH}."
echo "[entrypoint]   API_BASE_URL   = ${API_BASE_URL:-<not set — using default>}"
echo "[entrypoint]   ASSET_BASE_URL = ${ASSET_BASE_URL:-<not set>}"
echo "[entrypoint]   APP_ENV        = ${APP_ENV:-local}"

# ---------------------------------------------------------------------------
# Step 2: Inject nginx.conf from SSM Parameter Store (cz-css-1012)
# ---------------------------------------------------------------------------
echo "[entrypoint] Starting nginx configuration injection (cz-css-1012)..."

if [ -n "${NGINX_CONF}" ]; then
    # Write the SSM-injected nginx configuration to the nginx conf.d directory.
    # NGINX_CONF is populated by the ECS agent from SSM Parameter Store at
    # task startup via the `secrets` field in the task definition.
    echo "${NGINX_CONF}" > "${NGINX_CONF_PATH}"
    echo "[entrypoint] nginx.conf written from SSM Parameter Store (NGINX_CONF env var)."
elif [ -f "/etc/nginx/templates/nginx.conf.template" ]; then
    # Fallback: use envsubst on the bundled template (for local/non-ECS builds).
    # Resolves ${ASSET_BASE_URL} in the sub_filter directive at container start.
    echo "[entrypoint] NGINX_CONF not set — falling back to template-based config."
    envsubst '${ASSET_BASE_URL}' < /etc/nginx/templates/nginx.conf.template > "${NGINX_CONF_PATH}"
    echo "[entrypoint] nginx.conf written from template with envsubst substitution."
else
    echo "[entrypoint] WARNING: Neither NGINX_CONF nor template found. Using default nginx config."
fi

echo "[entrypoint] nginx configuration ready at ${NGINX_CONF_PATH}."

# Execute the CMD passed to this entrypoint (nginx -g 'daemon off;')
exec "$@"
