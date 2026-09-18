# =============================================================================
# Multi-Stage Dockerfile — Spring Boot 3.2.5 / Java 17
# Application: dashboard-app
# Target: AWS ECS Fargate
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Build Stage — Maven + Eclipse Temurin 17
# Compiles the Spring Boot application and produces an executable JAR.
# All build tooling (Maven, JDK, source files) is confined to this stage
# and is NOT present in the final runtime image.
# ---------------------------------------------------------------------------
FROM maven:3.9.4-eclipse-temurin-17 AS builder

WORKDIR /workspace

# Copy Maven POM first for dependency layer caching.
# Docker will reuse this layer on subsequent builds if pom.xml has not changed.
COPY pom.xml .

# Download all project dependencies offline — cached as a separate layer.
RUN mvn dependency:go-offline -B

# Copy the full application source code.
COPY src ./src

# Build the executable JAR, skipping tests (tests run in CI pipeline).
# Uses system `mvn` — never the Maven wrapper (mvnw/mvnw.cmd).
RUN mvn clean package -DskipTests -B

# ---------------------------------------------------------------------------
# Stage 2: Runtime Stage — Amazon Corretto 17
# Minimal production image containing only the compiled JAR and JRE.
# No build tools, no source files, no package managers.
# ---------------------------------------------------------------------------
FROM amazoncorretto:17

# Set timezone to UTC for consistent log timestamps across environments.
ENV TZ=UTC

# Create a non-root user and group for security best practices.
# Running as root inside a container is a security anti-pattern.
RUN groupadd --system --gid 1001 appgroup && \
    useradd --system --uid 1001 --gid appgroup --no-create-home appuser

WORKDIR /app

# Copy the executable JAR from the builder stage.
COPY --from=builder /workspace/target/*.jar app.jar

# Set ownership of the application directory to the non-root user.
RUN chown -R appuser:appgroup /app

# Switch to the non-root user.
USER appuser

# Expose the application port (matches server.port=8080 in application.properties).
EXPOSE 8080

# JVM tuning for containerised environments:
#   -XX:+UseContainerSupport        — honour cgroup CPU/memory limits
#   -XX:MaxRAMPercentage=75.0       — use up to 75% of container memory for heap
#   -XX:+UseG1GC                    — G1 garbage collector (default in Java 17)
#   -Djava.security.egd=...         — faster SecureRandom seeding in containers
#   -Dspring.profiles.active=docker — activate the docker Spring profile
ENV JAVA_OPTS="-XX:+UseContainerSupport \
               -XX:MaxRAMPercentage=75.0 \
               -XX:+UseG1GC \
               -Djava.security.egd=file:/dev/./urandom \
               -Dspring.profiles.active=docker"

# Use exec form with shell expansion for JAVA_OPTS.
# exec form ensures the JVM receives SIGTERM directly for graceful shutdown.
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
