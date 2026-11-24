# ---- Build stage ----
FROM maven:3.9.4-eclipse-temurin-17 AS builder
WORKDIR /workspace

# Cache dependencies: copy pom.xml first
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy sources and build
COPY src ./src
RUN mvn clean package -DskipTests -B

# ---- Runtime stage ----
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

ENV TZ=UTC \
    SPRING_PROFILES_ACTIVE=docker \
    SERVER_PORT=8080 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC"

RUN addgroup -S app && adduser -S app -G app

COPY --from=builder /workspace/target/*.jar /app/app.jar
RUN chown -R app:app /app

USER app
EXPOSE 8080

# exec form via sh so JAVA_OPTS expands and java receives signals (PID 1) for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
