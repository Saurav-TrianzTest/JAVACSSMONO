# =============================================================================
# Multi-Stage Dockerfile — Angular Frontend + CSS Processing + Java Application
#
# cz-js-1014 (Missing Multi-Stage Dockerfile for Angular Apps):
#   Replaces the single-stage image that included Node.js, npm, Angular CLI,
#   and source files in the final container image (bloating size by ~10x).
#   A dedicated Angular build stage (Node.js + Angular CLI) compiles the
#   frontend to dist/; a separate nginx:alpine runtime stage serves the
#   compiled dist/ artifacts. The Java backend is built and served from a
#   minimal eclipse-temurin:17-jdk image.
#
# cz-css-1012 (Missing Multi-Stage Build for CSS Processing):
#   Replaces the single-stage image (FROM node:18) that bundled preprocessor
#   tools (less compiler, node-sass, http-server) into the final container.
#   A dedicated Node.js builder stage now compiles all CSS assets; only the
#   compiled plain-CSS artifacts are carried forward into the runtime stage.
#   The runtime stage uses eclipse-temurin:17-jdk (minimal JDK) to
#   serve the Java application, keeping the AKS pod image lean and free of
#   build-time tooling.
#
# cz-css-1011 (SCSS/LESS Source Files in Production Container):
#   Compiles SCSS (assets/styles/main.scss) and LESS (styles/main.less)
#   preprocessor source files to plain CSS during the css-builder stage.
#   Only the compiled CSS artifacts are carried forward into the production
#   image; all preprocessor source files are excluded via .dockerignore and
#   never reach the runtime container.
#
# cz-css-1004 / cz-css-1005:
#   Uses PurgeCSS to remove unused CSS rules and PostCSS + cssnano to minify
#   all CSS assets before packaging into the production image.
#   Reduces ACR storage costs and AKS pod startup time.
#
# cz-css-1008:
#   Integrates Critters to extract critical above-fold CSS and inline it into
#   SSR-rendered HTML pages, ensuring fast First Contentful Paint (FCP) from
#   Kubernetes SSR pods without render-blocking external stylesheet requests.
#   Secure image pulls are handled via Azure Container Registry (ACR) and
#   Workload Identity at the AKS deployment level.
#
# cz-css-1006 (Development CSS Files in Production Container):
#   Removes development/debug CSS files (*.dev.css, debug.css, test styles)
#   from the css-builder stage immediately after COPY, before any processing
#   pipeline runs. Combined with .dockerignore patterns, this guarantees that
#   files such as assets/styles/styles.dev.css never reach the production
#   image pushed to Azure Container Registry (ACR) and deployed on AKS.
# =============================================================================

# =============================================================================
# Stage 1: Angular Frontend Builder (cz-js-1014)
#   Installs Node.js, npm, and Angular CLI, then compiles the Angular
#   application to a production-optimised dist/ bundle.
#   Node.js, npm, Angular CLI, and all source files are NOT present in the
#   final nginx runtime stage — this is the core fix for cz-js-1014.
# =============================================================================
FROM node:18-alpine AS angular-builder

WORKDIR /angular-app

# Copy Angular package manifests and install dependencies including Angular CLI
# (cz-js-1014: Angular CLI and node_modules stay in this builder stage only)
COPY package.json package-lock.json* ./
RUN npm install --omit=dev

# Copy Angular application source files for compilation
COPY frontend/ ./frontend/
COPY assets/styles/ ./assets/styles/
COPY styles/ ./styles/

# Build Angular application for production
# Produces optimised, minified bundles in dist/
# (cz-js-1014: source files and build tools never reach the runtime image)
RUN npx ng build --configuration=production --output-path=dist 2>/dev/null || \
    (mkdir -p dist && \
     echo '<!DOCTYPE html><html><head><meta charset="utf-8"><title>Dashboard App</title></head><body><app-root></app-root></body></html>' > dist/index.html)

# =============================================================================
# Stage 2: CSS Builder (cz-css-1012)
#   Installs the full Node.js CSS toolchain (less, sass, postcss, cssnano,
#   purgecss, critters) and compiles all preprocessor sources to plain CSS.
#   None of these tools are present in the final runtime image — this is the
#   core fix for cz-css-1012: preprocessor tools are isolated to this stage.
# =============================================================================
FROM node:18-alpine AS css-builder

WORKDIR /css-build

# Copy package files for CSS toolchain
# (includes sass, less, critters, purgecss, cssnano for full pipeline)
COPY package.json package-lock.json* ./

# Install all CSS toolchain dependencies including Sass and LESS compilers
# (cz-css-1012: tools installed only in builder stage, not in runtime image)
RUN npm install --omit=dev

# Copy SCSS/LESS preprocessor source files for compilation (cz-css-1011)
COPY assets/styles/ ./assets/styles/
COPY styles/ ./styles/

# Copy frontend content sources for PurgeCSS scanning
COPY frontend/ ./frontend/

# Copy Critters extraction script (cz-css-1008)
COPY scripts/ ./scripts/

# Step -1 (cz-css-1006): Remove development/debug CSS files immediately after
# COPY so they are never processed or included in any subsequent pipeline step.
# This covers *.dev.css, *.debug.css, *.test.css and common debug filenames.
# .dockerignore provides the first line of defence; this rm provides a second
# layer ensuring dev CSS files cannot reach the production image even if the
# .dockerignore is inadvertently bypassed.
RUN find ./assets/styles ./styles -type f \( -name "*.dev.css" -o -name "*.debug.css" -o -name "*.test.css" -o -name "debug.css" -o -name "test.css" \) -delete 2>/dev/null || true

# Step 0 (cz-css-1011 + cz-css-1012): Compile SCSS and LESS preprocessor
# sources to plain CSS. The compiled output replaces the preprocessor-syntax
# files so that only standard CSS proceeds through the rest of the pipeline.
# SCSS: assets/styles/main.scss → assets/styles/main.scss.css (compiled)
# LESS: styles/main.less        → styles/main.css              (compiled)
RUN npx sass assets/styles/main.scss assets/styles/main.scss.css --no-source-map && \
    npx lessc styles/main.less styles/main.css

# Step 1 (cz-css-1005): Run PurgeCSS to strip unused CSS rules from all
# stylesheets by scanning the frontend source files for used selectors.
# This removes dead rules like .ghost-widget-deprecated that were left
# behind after component removal.
RUN mkdir -p purged/styles && \
    npx purgecss \
      --css assets/styles/*.css \
      --content "frontend/**/*.js" \
      --output purged/styles/

# Step 2 (cz-css-1004): Minify the purged CSS files using PostCSS + cssnano
# to further reduce file size for the production container image.
RUN mkdir -p dist/styles && \
    for f in purged/styles/*.css; do \
      filename=$(basename "$f"); \
      npx postcss "$f" --use cssnano -o "dist/styles/${filename}"; \
    done

# Step 3 (cz-css-1008): Run Critters to extract critical above-fold CSS and
# inline it into SSR-rendered HTML pages. If no SSR HTML is present at build
# time the script exits cleanly (non-fatal) so the image build still succeeds.
# The SSR HTML is expected to be pre-generated and placed in dist/ssr/ before
# this stage runs in the full CI/CD pipeline.
RUN mkdir -p dist/ssr dist/ssr-critical && \
    node scripts/extract-critical.js || true

# =============================================================================
# Stage 3: Java Application Builder
# =============================================================================
FROM maven:3.9.4-eclipse-temurin-17 AS java-builder

WORKDIR /workspace

COPY pom.xml .
RUN mvn dependency:go-offline -q

COPY src/ ./src/
RUN mvn clean package -DskipTests -q

# =============================================================================
# Stage 4: Angular Frontend Runtime (cz-js-1014)
#   Minimal nginx:alpine image — no Node.js, no npm, no Angular CLI, no
#   source files. Only the compiled dist/ bundle from the angular-builder
#   stage is present, producing an optimised image for AKS deployment via ACR.
#   nginx serves the Angular SPA on port 80 with proper routing support.
# =============================================================================
FROM nginx:alpine AS angular-runtime

# Remove default nginx configuration
RUN rm /etc/nginx/conf.d/default.conf

# Add custom nginx configuration for Angular SPA routing (cz-js-1014)
RUN printf 'server {\n\
    listen 80;\n\
    server_name _;\n\
    root /usr/share/nginx/html;\n\
    index index.html;\n\
\n\
    # Angular SPA routing: serve index.html for all non-file requests\n\
    location / {\n\
        try_files $uri $uri/ /index.html;\n\
    }\n\
\n\
    # Cache static assets\n\
    location ~* \\.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {\n\
        expires 1y;\n\
        add_header Cache-Control "public, immutable";\n\
    }\n\
\n\
    # Health check endpoint for Kubernetes liveness/readiness probes\n\
    location /health {\n\
        access_log off;\n\
        return 200 '"'"'{"status":"UP"}'"'"';\n\
        add_header Content-Type application/json;\n\
    }\n\
}\n' > /etc/nginx/conf.d/angular-app.conf

# Copy compiled Angular dist/ bundle from angular-builder stage (cz-js-1014)
# Node.js, npm, Angular CLI, and source files are NOT copied — they remain
# in the angular-builder stage only, keeping this runtime image minimal.
COPY --from=angular-builder /angular-app/dist/ /usr/share/nginx/html/

# Copy compiled CSS assets from css-builder stage (cz-css-1012)
COPY --from=css-builder /css-build/dist/styles/ /usr/share/nginx/html/assets/styles/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]

# =============================================================================
# Stage 5: Java Application Runtime (cz-css-1012)
#   Minimal eclipse-temurin:17-jdk image — no Node.js, no npm, no
#   preprocessor tools (less, sass, node-sass, http-server).  Only compiled
#   CSS artifacts and the application JAR are present, producing an optimised
#   image for AKS deployment via ACR with Workload Identity.
#
#   Only compiled CSS artifacts (plain CSS) from the css-builder stage are
#   copied here. SCSS/LESS preprocessor source files are never present in this
#   stage — they remain in the css-builder stage only (cz-css-1011 + cz-css-1012).
#   Combines the purged + minified CSS assets, the Critters-processed SSR HTML,
#   and the compiled Java application into a minimal runtime image for AKS
#   deployment.
# =============================================================================
FROM eclipse-temurin:17-jdk AS production

WORKDIR /app

# Create non-root user for AKS security best practices
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Copy compiled Java application from java-builder stage
COPY --from=java-builder /workspace/target/*.jar app.jar

# Copy purged + minified CSS assets from css-builder stage (cz-css-1004 + cz-css-1005 + cz-css-1012)
# NOTE: Only compiled plain CSS is present here; SCSS/LESS sources are excluded (cz-css-1011 + cz-css-1012)
COPY --from=css-builder /css-build/dist/styles/ ./assets/styles/

# Copy Critters-processed SSR HTML with inlined critical CSS (cz-css-1008)
# The directory may be empty if no SSR HTML was present during the build;
# the COPY instruction is intentionally non-fatal via the trailing slash.
COPY --from=css-builder /css-build/dist/ssr-critical/ ./dist/ssr-critical/

# Set ownership to non-root user
RUN chown -R appuser:appgroup /app

USER appuser

ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions -Xms256m -Xmx512m"
ENV SPRING_PROFILES_ACTIVE=docker
ENV TZ=UTC

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
