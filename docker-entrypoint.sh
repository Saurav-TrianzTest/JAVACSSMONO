#!/bin/sh
# docker-entrypoint.sh — cz-css-1012 remediation
# Starts the Spring Boot application in the background, then launches nginx
# in the foreground so the container stays alive and nginx serves as the
# primary process (PID 1 equivalent for signal handling).

set -e

# Start Spring Boot application in the background
echo "Starting Spring Boot application..."
java -jar /app/app.jar &
JAVA_PID=$!

# Give Spring Boot a moment to initialise before nginx starts accepting traffic
sleep 5

# Start nginx in the foreground (keeps the container running)
echo "Starting nginx..."
exec nginx -g "daemon off;"
