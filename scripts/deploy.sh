#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${AWS_REGION:?AWS_REGION is required}"
: "${ECR_REPOSITORY_URI:?ECR_REPOSITORY_URI is required}"
: "${SERVICE_LIST:?SERVICE_LIST is required}"

APP_DIR="/opt/shoplite"
HEALTH_TIMEOUT=60
TLS_DIR="$APP_DIR/tls"
HTTPS_CONF="$APP_DIR/https-nginx.conf"
CERTBOT_DIR="$APP_DIR/certbot/www"

cd "$APP_DIR"

test -f .env || { echo "Missing /opt/shoplite/.env"; exit 1; }
test -f db/init.sql || { echo "Missing /opt/shoplite/db/init.sql"; exit 1; }

set -a
source .env
set +a

SERVER_NAME="${SERVER_NAME:-shoplite.test}"
REGISTRY="${ECR_REPOSITORY_URI%%/*}"

wait_healthy() {
  local NAME="$1"
  local DEADLINE=$((SECONDS + HEALTH_TIMEOUT))
  local STATUS="unknown"

  while (( SECONDS < DEADLINE )); do
    STATUS=$(docker inspect \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      "$NAME" 2>/dev/null || echo missing)

    if [[ "$STATUS" == "healthy" ]]; then
      echo "$NAME is healthy"
      return 0
    fi

    if [[ "$STATUS" == "exited" || "$STATUS" == "dead" || "$STATUS" == "missing" ]]; then
      break
    fi

    sleep 2
  done

  echo "ERROR: $NAME failed health check: $STATUS"
  docker logs --tail 20 "$NAME" || true
  return 1
}

echo "Authenticating to ECR"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "Preparing Docker networks"

docker network inspect frontend-net >/dev/null 2>&1 \
  || docker network create frontend-net

docker network inspect backend-net >/dev/null 2>&1 \
  || docker network create --internal backend-net

docker volume inspect pgdata >/dev/null 2>&1 \
  || docker volume create pgdata

# Preserve the existing PostgreSQL container and database volume.
if ! docker container inspect postgres >/dev/null 2>&1; then
  echo "Creating PostgreSQL"

  docker run -d \
    --name postgres \
    --network backend-net \
    --restart unless-stopped \
    --env-file .env \
    --health-cmd "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}" \
    --health-interval 5s \
    --health-timeout 3s \
    --health-retries 10 \
    -v pgdata:/var/lib/postgresql/data \
    -v "$APP_DIR/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
    postgres:17-alpine >/dev/null
elif [[ "$(docker inspect -f '{{.State.Running}}' postgres)" != "true" ]]; then
  docker start postgres >/dev/null
fi

wait_healthy postgres

echo "Pulling selected service images"

for SERVICE in $SERVICE_LIST; do
  docker pull "${ECR_REPOSITORY_URI}:${SERVICE}-${IMAGE_TAG}"
done

echo "Checking HTTPS configuration"

if [[ " $SERVICE_LIST " == *" frontend "* ]]; then
  test -s "$HTTPS_CONF" || {
    echo "ERROR: HTTPS Nginx configuration missing"
    exit 1
  }

  test -d "$TLS_DIR" || {
    echo "ERROR: TLS directory missing"
    exit 1
  }

  mkdir -p "$CERTBOT_DIR"
fi

echo "Deploying selected services"

for SERVICE in $SERVICE_LIST; do
  IMAGE="${ECR_REPOSITORY_URI}:${SERVICE}-${IMAGE_TAG}"

  if [[ "$SERVICE" == "frontend" ]]; then
    TOKEN=$(curl -fsS --max-time 2 -X PUT \
      http://169.254.169.254/latest/api/token \
      -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)

    PUBLIC_IP=""
    if [[ -n "$TOKEN" ]]; then
      PUBLIC_IP=$(curl -fsS --max-time 2 \
        -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
    fi

    echo "Validating HTTPS Nginx configuration"

    docker run --rm \
      --user root \
      --network frontend-net \
      --env SERVER_NAME="$SERVER_NAME" \
      --env SERVER_ALIASES="$PUBLIC_IP" \
      -v "$HTTPS_CONF:/etc/nginx/templates/default.conf.template:ro" \
      -v "$TLS_DIR:/etc/nginx/tls:ro" \
      -v "$CERTBOT_DIR:/var/www/certbot:ro" \
      --entrypoint /bin/sh \
      "$IMAGE" -c \
      'envsubst '\''${SERVER_NAME} ${SERVER_ALIASES}'\'' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf && nginx -t'

    docker rm -f frontend >/dev/null 2>&1 || true

    docker run -d \
      --name frontend \
      --network frontend-net \
      --restart unless-stopped \
      --env-file .env \
      -e SERVER_ALIASES="$PUBLIC_IP" \
      -p 80:80 \
      -p 443:443 \
      -v "$HTTPS_CONF:/etc/nginx/templates/default.conf.template:ro" \
      -v "$TLS_DIR:/etc/nginx/tls:ro" \
      -v "$CERTBOT_DIR:/var/www/certbot:ro" \
      "$IMAGE" >/dev/null

  else
    docker rm -f "$SERVICE" >/dev/null 2>&1 || true

    docker run -d \
      --name "$SERVICE" \
      --network backend-net \
      --restart unless-stopped \
      --env-file .env \
      "$IMAGE" >/dev/null

    docker network connect frontend-net "$SERVICE"
  fi

  wait_healthy "$SERVICE"
done

echo "Running smoke tests"

for SERVICE in $SERVICE_LIST; do
  case "$SERVICE" in
    frontend)
      URL="https://127.0.0.1/health"
      ;;
    catalog)
      URL="https://127.0.0.1/api/catalog/health"
      ;;
    inventory)
      URL="https://127.0.0.1/api/inventory/health"
      ;;
    orders)
      URL="https://127.0.0.1/api/orders/health"
      ;;
    *)
      echo "ERROR: Unknown service: $SERVICE"
      exit 1
      ;;
  esac

  if ! curl -kfsS --max-time 10 \
    --resolve "${SERVER_NAME}:443:127.0.0.1" \
    "$URL"; then
    echo "ERROR: $SERVICE smoke test failed"
    exit 1
  fi

  echo
done

echo "Cleaning unused images older than 7 days"
docker image prune -af --filter until=168h

echo "Deployment successful: $SERVICE_LIST at $IMAGE_TAG"
