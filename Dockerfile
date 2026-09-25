# =============================================================================
# Multi-Stage Dockerfile for dashboard-app (Spring Boot 3.2.5 / Java 17)
# Builder : maven:3.9.4-eclipse-temurin-17
# Runtime : eclipse-temurin:17-jdk  (explicit base image)
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: builder
# Downloads all Maven dependencies (cached layer) then compiles and packages
# the Spring Boot fat-JAR.  The Maven toolchain is NOT present in the runtime.
# -----------------------------------------------------------------------------
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy dependency manifests first to leverage Docker layer caching.
# The dependency layer is only invalidated when pom.xml changes.
COPY pom.xml .

# Pre-download all dependencies so subsequent builds are fast.
RUN mvn dependency:go-offline -B

# Copy the full source tree and build the executable JAR.
# CRITICAL: wrapper scripts (mvnw / mvnw.cmd / .mvn/) are excluded via
# .dockerignore and are NEVER referenced here.
COPY src ./src

RUN mvn clean package -DskipTests -B

# -----------------------------------------------------------------------------
# Stage 2: runtime
# Minimal eclipse-temurin:17-jdk image — no Maven, no build tools.
# Only the compiled JAR and a non-root user are present.
# -----------------------------------------------------------------------------
FROM eclipse-temurin:17-jdk

# Timezone configuration
ENV TZ=UTC

# Create a non-root user for security
RUN groupadd --system appgroup && \
    useradd  --system --gid appgroup --home /app --shell /bin/false appuser

WORKDIR /app

# Copy the fat-JAR produced by the builder stage
COPY --from=builder /workspace/target/*.jar app.jar

# Ensure the non-root user owns the application directory
RUN chown -R appuser:appgroup /app

USER appuser

# JVM tuning: container-aware heap sizing, G1GC, graceful shutdown support
ENV JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -XX:+UseG1GC \
               -Djava.security.egd=file:/dev/./urandom \
               -Dfile.encoding=UTF-8 \
               -Duser.timezone=UTC"

# Spring profile active in container environments
ENV SPRING_PROFILES_ACTIVE=docker

# Application port (matches server.port in application.properties)
EXPOSE 8080

# Use exec form so that SIGTERM is forwarded directly to the JVM,
# enabling Spring Boot's graceful shutdown.
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
