# =============================================================================
# Multi-Stage Dockerfile for dashboard-app (Spring Boot 3.2.5 / Java 17)
# Target Platform: AWS EKS
# Builder : maven:3.9.4-eclipse-temurin-17
# Runtime : amazoncorretto:17
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build Stage
# Compiles the Spring Boot application and produces an executable JAR.
# All Maven tooling and source files remain in this stage only.
# -----------------------------------------------------------------------------
FROM maven:3.9.4-eclipse-temurin-17 AS builder
WORKDIR /workspace

# Copy dependency descriptor first to leverage Docker layer caching.
# Dependencies are downloaded before source code is copied, so they are
# re-used on subsequent builds when only source files change.
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy application source and build the executable JAR
COPY src ./src
RUN mvn clean package -DskipTests -B

# -----------------------------------------------------------------------------
# Stage 2: Runtime Stage
# Minimal production image containing only the compiled JAR.
# No build tools, source files, or development dependencies are included.
# -----------------------------------------------------------------------------
FROM amazoncorretto:17
WORKDIR /app

# Create a non-root user for security best practices
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --no-create-home appuser

# Copy the executable JAR from the builder stage
COPY --from=builder /workspace/target/*.jar app.jar

# Set ownership of the application directory
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Application port (matches server.port in application.properties)
EXPOSE 8080

# JVM tuning: container-aware memory settings with graceful shutdown support
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
