#!/usr/bin/env bash
# ShopLite Phase 1: start all five containers in order, by hand (no Compose).
#
#   TAG=1.0.0 ./scripts/up.sh
#
# Safe to run twice: networks/volume are created only if missing, and an
# existing container is replaced. Waits for each tier to report healthy before
# starting the next one.
set -euo pipefail

cd "$(dirname "$0")/.."

TAG=${TAG:-1.0.0}
POSTGRES_IMAGE=${POSTGRES_IMAGE:-postgres:17-alpine}
HEALTH_TIMEOUT=${HEALTH_TIMEOUT:-60}

if [[ ! -f .env ]]; then
  echo "error: .env not found. Copy .env.example to .env and set real values." >&2
  echo "       cp .env.example .env" >&2
  exit 1
fi

# Export .env so this script can use POSTGRES_USER/POSTGRES_DB in the health command.
set -a
# shellcheck disable=SC1091
source .env
set +a

log() { printf '\n==> %s\n' "$*"; }

wait_healthy() {
  local name=$1
  local deadline=$((SECONDS + HEALTH_TIMEOUT))
  local status

  while (( SECONDS < deadline )); do
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo missing)
    if [[ $status == healthy ]]; then
      echo "    $name is healthy"
      return 0
    fi
    if [[ $status == exited || $status == dead || $status == missing ]]; then
      break
    fi
    sleep 2
  done

  echo "error: $name did not become healthy within ${HEALTH_TIMEOUT}s (last status: $status)" >&2
  echo "--- last 20 log lines from $name ---" >&2
  docker logs --tail 20 "$name" >&2 || true
  exit 1
}

# Replace a container with the same name, if any. Keeps the pgdata volume.
replace() {
  docker rm -f "$1" >/dev/null 2>&1 || true
}

log "Networks and volume"
docker network inspect frontend-net >/dev/null 2>&1 || docker network create frontend-net
# Internal network: no route out, and unreachable from the host.
docker network inspect backend-net >/dev/null 2>&1 || docker network create --internal backend-net
docker volume inspect pgdata >/dev/null 2>&1 || docker volume create pgdata

log "Postgres (backend-net only, data in pgdata)"
replace postgres
# The official image has no health check: add one.
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
  -v "$PWD/db/init.sql:/docker-entrypoint-initdb.d/init.sql:ro" \
  "$POSTGRES_IMAGE" >/dev/null
wait_healthy postgres

log "Backends (backend-net, then attached to frontend-net)"
for service in catalog inventory orders; do
  case $service in
    catalog)   port=3000 ;;
    inventory) port=8081 ;;
    orders)    port=8082 ;;
  esac

  replace "$service"
  docker run -d \
    --name "$service" \
    --network backend-net \
    --restart unless-stopped \
    --env-file .env \
    "shop-$service:$TAG" >/dev/null
  docker network connect frontend-net "$service"
  wait_healthy "$service"
done

log "Frontend (frontend-net only, the only published port)"
replace frontend
docker run -d \
  --name frontend \
  --network frontend-net \
  --restart unless-stopped \
  --env-file .env \
  -p 80:80 \
  "shop-frontend:$TAG" >/dev/null
wait_healthy frontend

cat <<EOF

ShopLite is up (TAG=$TAG).

  Frontend:  http://${SERVER_NAME:-shoplite.test}
  Backends:  private; reachable only from frontend-net and backend-net.

Add the name to /etc/hosts once, if you haven't:
  127.0.0.1 ${SERVER_NAME:-shoplite.test}

Stop it with ./scripts/down.sh
EOF
