#!/bin/sh
# =============================================================================
# docker-entrypoint.sh
# =============================================================================
# Resolves runtime environment variables inside nginx.conf at container startup,
# generates the Angular runtime-config.json from ECS Fargate Secrets Manager
# injected environment variables, then launches NGINX in the foreground.
#
# Required environment variables (supplied via ECS Fargate task definition
# `environment` or `secrets` fields, sourced from AWS Secrets Manager /
# SSM Parameter Store):
#
#   [cz-js-1014] Angular Runtime Environment Config (from Secrets Manager):
#   API_BASE_URL         — e.g. https://api.example.com
#                          Secrets Manager path: /app/angular/api-base-url
#   FEATURE_FLAGS        — JSON string of feature flag overrides
#                          Secrets Manager path: /app/angular/feature-flags
#   APP_ENV              — e.g. production | staging | development
#                          Secrets Manager path: /app/angular/app-env
#   COGNITO_USER_POOL_ID — AWS Cognito User Pool ID
#                          Secrets Manager path: /app/angular/cognito-user-pool-id
#   COGNITO_CLIENT_ID    — AWS Cognito App Client ID
#                          Secrets Manager path: /app/angular/cognito-client-id
#
#   NGINX_CONF_CONTENT   — [cz-css-1012] Full nginx.conf content injected from
#                          AWS SSM Parameter Store via the ECS Fargate task
#                          definition `secrets` field.
#                          SSM Parameter Store path: /app/nginx/nginx-conf
#                          When present, this value is written directly to
#                          /etc/nginx/nginx.conf, enabling environment-specific
#                          routing rules without rebuilding the container image.
#                          Falls back to the bundled template when absent.
#
#   ASSET_BASE_URL       — [cz-css-1001] e.g. https://assets.northwind.io:9000
#                          SSM Parameter Store path: /app/nginx/asset-base-url
#
#   CRITICAL_CSS_CONTENT — [cz-css-1008] Critical above-fold CSS string injected
#                          from SSM Parameter Store path: /app/css/critical-content
#                          Inlined into HTML <head> by the SSR layer.
# =============================================================================

set -e

# ---------------------------------------------------------------------------
# [cz-js-1014] Angular Runtime Environment Config — Secrets Manager Injection
#
# The ECS Fargate task definition `secrets` field maps Secrets Manager ARNs
# to environment variables (API_BASE_URL, FEATURE_FLAGS, APP_ENV, etc.).
#
# At container startup, this script writes a runtime-config.json file into
# the Angular app's asset directory. The Angular app reads this file via
# APP_INITIALIZER (or a config service) to obtain environment-specific values
# at runtime — replacing hardcoded environment.prod.ts / environment.ts files
# that would otherwise be baked into the container image.
#
# This enables single-image promotion across dev / staging / production:
#   - No image rebuild required when API endpoints or feature flags change
#   - Secrets are never stored in the container image layers
#   - Each ECS task receives its own environment-specific configuration
# ---------------------------------------------------------------------------

API_BASE_URL="${API_BASE_URL:-}"
FEATURE_FLAGS="${FEATURE_FLAGS:-{}}"
APP_ENV="${APP_ENV:-production}"
COGNITO_USER_POOL_ID="${COGNITO_USER_POOL_ID:-}"
COGNITO_CLIENT_ID="${COGNITO_CLIENT_ID:-}"

RUNTIME_CONFIG_DIR="/usr/share/nginx/html/assets"
RUNTIME_CONFIG_FILE="${RUNTIME_CONFIG_DIR}/runtime-config.json"

echo "[entrypoint][cz-js-1014] Generating Angular runtime-config.json from Secrets Manager environment variables..."
echo "[entrypoint][cz-js-1014]   APP_ENV=${APP_ENV}"
echo "[entrypoint][cz-js-1014]   API_BASE_URL=${API_BASE_URL}"
echo "[entrypoint][cz-js-1014]   COGNITO_USER_POOL_ID=${COGNITO_USER_POOL_ID}"
echo "[entrypoint][cz-js-1014]   FEATURE_FLAGS=${FEATURE_FLAGS}"

# Ensure the assets directory exists
mkdir -p "${RUNTIME_CONFIG_DIR}"

# Write runtime-config.json — Angular reads this via APP_INITIALIZER at startup.
# All values originate from ECS Fargate Secrets Manager injection (never hardcoded).
cat > "${RUNTIME_CONFIG_FILE}" <<EOF
{
  "apiBaseUrl": "${API_BASE_URL}",
  "appEnv": "${APP_ENV}",
  "cognitoUserPoolId": "${COGNITO_USER_POOL_ID}",
  "cognitoClientId": "${COGNITO_CLIENT_ID}",
  "featureFlags": ${FEATURE_FLAGS}
}
EOF

echo "[entrypoint][cz-js-1014] runtime-config.json written to ${RUNTIME_CONFIG_FILE}"

# ---------------------------------------------------------------------------
# [cz-css-1012] nginx.conf injection from AWS SSM Parameter Store
#
# The ECS Fargate task definition `secrets` field maps the SSM parameter
#   /app/nginx/nginx-conf  →  NGINX_CONF_CONTENT environment variable.
#
# If NGINX_CONF_CONTENT is populated (runtime injection path):
#   Write the SSM-supplied content directly to /etc/nginx/nginx.conf.
#   This allows environment-specific routing rules (dev / staging / prod)
#   to be applied without rebuilding the container image.
#
# If NGINX_CONF_CONTENT is absent (local development / CI fallback path):
#   Run envsubst on the bundled /etc/nginx/nginx.conf.template to resolve
#   $ASSET_BASE_URL and write the result to /etc/nginx/conf.d/default.conf.
# ---------------------------------------------------------------------------

NGINX_CONF_CONTENT="${NGINX_CONF_CONTENT:-}"
ASSET_BASE_URL="${ASSET_BASE_URL:-}"

# [cz-css-1008] CRITICAL_CSS_CONTENT is injected from AWS SSM Parameter Store
# via the ECS Fargate task definition environment. The SSR layer reads this
# variable and inlines it into the HTML <head> as a <style> tag, ensuring
# fast First Contentful Paint without render-blocking external CSS requests.
CRITICAL_CSS_CONTENT="${CRITICAL_CSS_CONTENT:-}"

if [ -n "${NGINX_CONF_CONTENT}" ]; then
    # ── Runtime injection path (ECS Fargate with SSM secrets) ────────────────
    echo "[entrypoint][cz-css-1012] NGINX_CONF_CONTENT detected — writing SSM-injected nginx.conf..."
    # Write the SSM-supplied nginx.conf content to the active configuration path.
    printf '%s' "${NGINX_CONF_CONTENT}" > /etc/nginx/nginx.conf
    echo "[entrypoint][cz-css-1012] nginx.conf written from SSM Parameter Store (/app/nginx/nginx-conf)."
else
    # ── Fallback path (local dev / CI — no SSM injection) ────────────────────
    echo "[entrypoint][cz-css-1012] NGINX_CONF_CONTENT not set — falling back to bundled template."
    echo "[entrypoint] Resolving ASSET_BASE_URL='${ASSET_BASE_URL}' in nginx.conf template..."
    # Substitute $ASSET_BASE_URL in the bundled template and write to conf.d.
    envsubst '${ASSET_BASE_URL}' \
        < /etc/nginx/nginx.conf.template \
        > /etc/nginx/conf.d/default.conf
    echo "[entrypoint] nginx.conf resolved from bundled template."
fi

echo "[entrypoint] CRITICAL_CSS_CONTENT env var present: $([ -n "${CRITICAL_CSS_CONTENT}" ] && echo 'yes' || echo 'no (using default)')"
echo "[entrypoint] Starting NGINX..."

# Hand off to NGINX (PID 1)
exec nginx -g "daemon off;"
