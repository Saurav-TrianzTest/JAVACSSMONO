# Multi-stage build (cz-js-1014): Node.js build tooling stays in the build stage; only compiled output ships in nginx:alpine
# ---- Build stage: compile CSS and strip unused rules with PurgeCSS ----
FROM node:18 AS build
WORKDIR /app
COPY . .
# Safety net (cz-css-1006): ensure dev/debug CSS never reaches the runtime image
RUN find /app -type f \( -name "*.dev.css" -o -name "debug.css" -o -name "*.debug.css" -o -name "*.test.css" \) -delete
RUN npm install less && npm run build:css
RUN npm install --no-save purgecss && \
    mkdir -p /app/dist/styles && \
    npx purgecss \
      --css "assets/styles/*.css" \
      --content "**/*.html" "frontend/**/*.js" "frontend/**/*.jsx" "src/main/resources/**/*.html" \
      --output /app/dist/styles

# Extract critical CSS with Critters and inline it into HTML (cz-css-1008)
RUN npm install --no-save critters && \
    node scripts/inline-critical-css.js

# ---- Runtime stage (cz-css-1012): minimal nginx:alpine serving only compiled output ----
FROM nginx:alpine
COPY --from=build /app/assets /usr/share/nginx/html/assets
COPY --from=build /app/cdn-assets /usr/share/nginx/html/cdn-assets
COPY --from=build /app/dist/styles/ /usr/share/nginx/html/assets/styles/
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
