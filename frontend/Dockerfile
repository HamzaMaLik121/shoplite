# ShopLite frontend: React (Vite) built once, served by nginx.
# Stage 1 only needs the build output; nothing from node_modules ships.

FROM node:26-alpine AS build
WORKDIR /app

# Dependency files first, so a source change doesn't reinstall node_modules.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build


# alpine-slim drops the dynamic modules nobody uses here; every MB counts
# against the 60 MB budget.
FROM nginx:1.27-alpine-slim AS runtime

# Run as the "nginx" user. The capability lets that non-root process bind :80
# even on hosts where unprivileged low ports are disabled.
# Alpine repos keep only current versions; the base image tag is the pin.
# hadolint ignore=DL3018
RUN apk add --no-cache --virtual .setcap libcap \
    && setcap 'cap_net_bind_service=+ep' /usr/sbin/nginx \
    && apk del .setcap \
    && mkdir -p /etc/nginx/templates /var/cache/nginx \
    && chown -R nginx:nginx /etc/nginx /var/cache/nginx /run /usr/share/nginx

# Only ${SERVER_NAME} is substituted in the template; nginx's own $variables
# ($host, $uri, ...) are left alone.
ENV NGINX_ENVSUBST_FILTER=^SERVER_NAME$ \
    SERVER_NAME=localhost

COPY nginx.conf /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html

USER nginx

EXPOSE 80

# The default server returns 444 for every other Host, so send the real one.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- --header="Host: $SERVER_NAME" http://127.0.0.1/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
