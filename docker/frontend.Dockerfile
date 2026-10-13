# ---- build: compile the React app ----
FROM node:22-alpine AS build
WORKDIR /app
COPY application/frontend/package.json ./
RUN npm install --no-audit --no-fund
COPY application/frontend/ ./
RUN npm run build

# ---- runtime: unprivileged nginx (runs as uid 101, listens on 8080) ----
FROM nginxinc/nginx-unprivileged:1.31-alpine3.24
USER root
RUN apk upgrade --no-cache
COPY docker/nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
ENV BACKEND_URL=http://backend:8000 NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1
USER 101
EXPOSE 8080
