# ShopLite catalog: Node.js + Express, owns the products table.

FROM node:26-alpine AS deps
WORKDIR /app

# Dependency files first, so a source change doesn't reinstall node_modules.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# The official node image ships npm and build headers (~25 MB) and an
# unstripped binary. Neither is needed to run the service.
FROM node:26-alpine AS node
# Build-stage tool only; the base image tag is the pin.
# hadolint ignore=DL3018
RUN apk add --no-cache --virtual .strip binutils \
    && cp /usr/local/bin/node /node \
    && strip /node \
    && apk del .strip


# Plain Alpine (same musl version as the builder) keeps the runtime small.
FROM alpine:3.24.4 AS runtime
# Alpine repos keep only current versions; the base image tag is the pin.
# hadolint ignore=DL3018
RUN apk add --no-cache libstdc++ libgcc libatomic \
    && addgroup -S app \
    && adduser -S -G app app

WORKDIR /app
ENV NODE_ENV=production \
    PORT=3000

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/package.json ./package.json
COPY src ./src
COPY --from=node /node /usr/local/bin/node

USER app

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://127.0.0.1:3000/health || exit 1

CMD ["node", "src/index.js"]
