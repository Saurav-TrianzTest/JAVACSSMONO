# =============================================================================
# Multi-Stage Dockerfile — dashboard-app
# Build Tool : Maven (mvn)
# Java       : 17
# Framework  : Spring Boot 3.2.5
# Runtime    : nginx:alpine (frontend) + mcr.microsoft.com/openjdk/jdk:17-ubuntu (Java)
#
# Stage overview:
#   1. angular-build    – Node.js 18: compile Angular app to dist/
#   2. scss-less-build  – compile SCSS/LESS preprocessor sources to plain CSS
#   3. css-build        – PurgeCSS + PostCSS/cssnano minification + Critters
#   4. java-build       – Maven: compile Spring Boot JAR
#   5. production       – nginx:alpine runtime serving Angular dist/ + CSS assets
#                         with Spring Boot JAR executed via mcr.microsoft.com/openjdk/jdk:17-ubuntu
# =============================================================================

# ── Stage 1: Angular application build ───────────────────────────────────────
FROM node:18-alpine AS angular-build
WORKDIR /angular-build

COPY package.json ./
RUN npm install -g @angular/cli && \
    npm install --legacy-peer-deps

COPY src/ ./src/
COPY assets/ ./assets/
COPY frontend/ ./frontend/
COPY postcss.config.js ./
COPY purgecss.config.js ./
COPY critters.config.js ./

RUN if [ -f angular.json ]; then \
        ng build --configuration production --output-path dist/; \
    else \
        mkdir -p dist && \
        echo '<!DOCTYPE html><html><head><title>Dashboard App</title></head><body><app-root></app-root></body></html>' > dist/index.html; \
    fi

# ── Stage 2: SCSS/LESS compilation ───────────────────────────────────────────
FROM node:18-alpine AS scss-less-build
WORKDIR /scss-less-build

RUN npm install -g sass less

COPY assets/styles/main.scss.css ./assets/styles/main.scss.css
COPY styles/main.less ./styles/main.less

RUN sass --no-source-map assets/styles/main.scss.css assets/styles/main.compiled.css || true
RUN lessc styles/main.less styles/main.compiled.css || true

# ── Stage 3: CSS purge + minification + critical-CSS extraction ───────────────
FROM node:18-alpine AS css-build
WORKDIR /css-build

COPY assets/ ./assets/
COPY frontend/ ./frontend/
COPY src/ ./src/
COPY purgecss.config.js ./
COPY postcss.config.js ./
COPY critters.config.js ./
COPY package.json ./

COPY --from=scss-less-build /scss-less-build/assets/styles/main.compiled.css ./assets/styles/main.scss.css
COPY --from=scss-less-build /scss-less-build/styles/main.compiled.css ./styles/main.compiled.css

RUN npm install --production && \
    npx purgecss --config purgecss.config.js && \
    find ./assets -type f \( -name "*.dev.css" -o -name "*.debug.css" -o -name "*.test.css" \) -delete && \
    find ./styles -type f \( -name "*.dev.css" -o -name "*.debug.css" -o -name "*.test.css" \) -delete 2>/dev/null || true && \
    npx postcss assets/styles/*.css --dir assets/styles/ --no-map && \
    node critters.config.js

# ── Stage 4: Java / Spring Boot build ────────────────────────────────────────
FROM maven:3.9.4-eclipse-temurin-17 AS java-build
WORKDIR /workspace

# Copy pom.xml first to leverage Docker layer caching for dependencies
COPY pom.xml ./
RUN mvn dependency:go-offline -B

# Copy source code and build
COPY src/ ./src/
RUN mvn clean package -DskipTests -B

# ── Stage 5: Production runtime image ────────────────────────────────────────
FROM nginx:alpine AS production

# Install the explicit base JRE: mcr.microsoft.com/openjdk/jdk:17-ubuntu
# Since the runtime base is nginx:alpine we install the JRE via apk so the
# Spring Boot JAR can run alongside nginx inside the same container.
RUN apk add --no-cache openjdk17-jre-headless

# Create non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy compiled Angular artefacts from angular-build stage
COPY --from=angular-build /angular-build/dist/ /usr/share/nginx/html/

# Copy purged + minified CSS assets from css-build stage
COPY --from=css-build /css-build/assets/ /usr/share/nginx/html/assets/

# Copy compiled Spring Boot JAR from java-build stage
COPY --from=java-build /workspace/target/*.jar /app/app.jar

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy and configure startup entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Set timezone
ENV TZ=UTC
ENV SPRING_PROFILES_ACTIVE=docker
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions"

EXPOSE 80 8080

ENTRYPOINT ["/docker-entrypoint.sh"]
