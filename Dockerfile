FROM node:18
WORKDIR /app
COPY . .
RUN npm install less && npm run build:css
EXPOSE 80
CMD ["npx", "http-server", "-p", "80"]
