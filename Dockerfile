# =============================================================================
# Multi-Stage Dockerfile — dashboard-app
# Builder : maven:3.9.4-eclipse-temurin-17
# Runtime : amazoncorretto:17
# Target  : Azure AKS
# =============================================================================

# ── Stage 1: Build ────────────────────────────────────────────────────────────
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy dependency manifests first to leverage Docker layer caching
COPY pom.xml .

# Download all dependencies (cached layer — only invalidated when pom.xml changes)
RUN mvn dependency:go-offline -B

# Copy the full source tree (wrapper files are excluded via .dockerignore)
COPY src ./src

# Build the fat JAR, skipping tests
RUN mvn clean package -DskipTests -B

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM amazoncorretto:17

WORKDIR /app

# Create a non-root user for security
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --no-create-home appuser

# Copy the fat JAR from the builder stage
COPY --from=builder /workspace/target/*.jar app.jar

# Set ownership
RUN chown -R appuser:appgroup /app

USER appuser

# Application port (matches server.port in application.properties)
EXPOSE 8080

# JVM tuning: container-aware memory settings + graceful shutdown signal
ENV JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -XX:+UnlockExperimentalVMOptions \
               -Xms256m \
               -Xmx512m \
               -Djava.security.egd=file:/dev/./urandom \
               -Dfile.encoding=UTF-8 \
               -Duser.timezone=UTC"

ENV SPRING_PROFILES_ACTIVE=docker

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
