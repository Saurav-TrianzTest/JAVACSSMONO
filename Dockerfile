# =============================================================================
# Dockerfile — Multi-Stage Build for Spring Boot Java Application
# Project: dashboard-app
# Java Version: 17
# Build Tool: Maven
# Framework: Spring Boot 3.2.5
# =============================================================================

# ── Stage 1: Maven Builder ────────────────────────────────────────────────────
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy Maven build descriptor first to leverage Docker layer caching.
# Dependencies are only re-downloaded when pom.xml changes.
COPY pom.xml .

# Download all dependencies offline so subsequent builds are faster.
RUN mvn dependency:go-offline -B

# Copy the full application source into the builder stage.
COPY src ./src

# Build the Spring Boot fat JAR, skipping tests for faster image builds.
# CRITICAL: Uses system `mvn` — never the Maven wrapper (mvnw/mvnw.cmd).
RUN mvn clean package -DskipTests -B

# ── Stage 2: Minimal JRE Runtime ─────────────────────────────────────────────
# Explicit base image provided: mcr.microsoft.com/openjdk/jdk:17-ubuntu
FROM mcr.microsoft.com/openjdk/jdk:17-ubuntu

# Set timezone for consistent log timestamps
ENV TZ=UTC

# Create a non-root user and group for security best practices
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --home /app --shell /bin/false appuser

WORKDIR /app

# Copy the compiled fat JAR from the builder stage
COPY --from=builder /workspace/target/*.jar app.jar

# Set ownership to the non-root user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# JVM tuning: container-aware memory settings
# -XX:+UseContainerSupport  — enables JVM to respect cgroup memory limits
# -XX:MaxRAMPercentage=75.0 — use up to 75% of container memory for heap
# -Xms256m                  — initial heap size
# -Xmx512m                  — maximum heap size
# -XX:+UseG1GC              — G1 garbage collector (good for containerised workloads)
# -Djava.security.egd       — faster SecureRandom seeding
ENV JAVA_OPTS="-XX:+UseContainerSupport \
  -XX:MaxRAMPercentage=75.0 \
  -Xms256m \
  -Xmx512m \
  -XX:+UseG1GC \
  -Djava.security.egd=file:/dev/./urandom \
  -Dfile.encoding=UTF-8 \
  -Duser.timezone=UTC"

# Spring Boot profile — override at runtime via ECS task environment variables
ENV SPRING_PROFILES_ACTIVE=docker

# Application port as defined in application.properties (server.port=8080)
EXPOSE 8080

# Use exec form for proper signal handling (SIGTERM → graceful shutdown)
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
