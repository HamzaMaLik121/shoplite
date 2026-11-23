#!/usr/bin/env bash
# Starts the whole ShopLite stack with plain docker commands.
# Usage: TAG=1.0.0 ./scripts/up.sh
set -euo pipefail

cd "$(dirname "$0")/.."

TAG="${TAG:-1.0.0}"
IMAGE_PREFIX="${IMAGE_PREFIX:-shop-}"
SERVER_NAME="${SERVER_NAME:-shoplite.test}"
WAIT_SECONDS=60

[ -f .env ] || { echo "ERROR: .env not found. Copy .env.example to .env first."; exit 1; }

image() { echo "${IMAGE_PREFIX}$1:${TAG}"; }

wait_healthy() {
  local deadline=$((SECONDS + WAIT_SECONDS))
  for name in "$@"; do
    echo "Waiting for $name to be healthy..."
    while true; do
      status=$(docker inspect --format '{{.State.Health.Status}}' "$name" 2>/dev/null || echo "missing")
      [ "$status" = "healthy" ] && { echo "  $name is healthy"; break; }
      if [ "$SECONDS" -ge "$deadline" ]; then
        echo "ERROR: $name not healthy after ${WAIT_SECONDS}s (status: $status). Last 20 log lines:"
        docker logs --tail 20 "$name" || true
        exit 1
      fi
      sleep 2
    done
  done
}

docker network inspect frontend-net >/dev/null 2>&1 || docker network create frontend-net
docker network inspect backend-net  >/dev/null 2>&1 || docker network create --internal backend-net
docker volume  inspect pgdata       >/dev/null 2>&1 || docker volume create pgdata

docker rm -f postgres >/dev/null 2>&1 || true
docker run -d --name postgres \
  --network backend-net \
  --restart unless-stopped \
  --env-file .env \
  -v pgdata:/var/lib/postgresql/data \
  -v "$(pwd)/db/init.sql":/docker-entrypoint-initdb.d/init.sql:ro \
  --health-cmd 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
  --health-interval 5s --health-timeout 3s --health-retries 10 \
  postgres:17-alpine
wait_healthy postgres

for svc in catalog inventory orders; do
  docker rm -f "$svc" >/dev/null 2>&1 || true
  docker run -d --name "$svc" \
    --network backend-net \
    --restart unless-stopped \
    --env-file .env \
    "$(image "$svc")"
  docker network connect frontend-net "$svc"
done
wait_healthy catalog inventory orders

docker rm -f frontend >/dev/null 2>&1 || true
docker run -d --name frontend \
  --network frontend-net \
  --restart unless-stopped \
  -p 80:80 \
  -e SERVER_NAME="$SERVER_NAME" \
  "$(image frontend)"
wait_healthy frontend

echo "All 5 containers are up. Open http://${SERVER_NAME}"
