#!/usr/bin/env bash
# ShopLite Phase 1: start all five containers in order, by hand (no Compose).
#
#   ./scripts/up.sh                     # build anything missing, tag 1.0.0
#   TAG=1.0.0 ./scripts/up.sh
#   REGISTRY=123.dkr.ecr.eu-west-1.amazonaws.com ./scripts/up.sh   # pull instead
#
# Safe to run twice: networks/volume are created only if missing, and an
# existing container is replaced. Nothing is started until every image is
# present, and a failed start removes what it started, so the host is never
# left half-up. Waits for each tier to report healthy before starting the next.
set -euo pipefail

cd "$(dirname "$0")/.."

TAG=${TAG:-1.0.0}
POSTGRES_IMAGE=${POSTGRES_IMAGE:-postgres:17-alpine}
HEALTH_TIMEOUT=${HEALTH_TIMEOUT:-60}

# Set REGISTRY to pull shop-* images from a registry instead of building them.
REGISTRY=${REGISTRY:-}
IMAGE_PREFIX=${IMAGE_PREFIX:-${REGISTRY:+$REGISTRY/}}

if [[ ! -f .env ]]; then
  echo "error: .env not found. Copy .env.example to .env and set real values." >&2
  echo "       cp .env.example .env" >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "error: cannot talk to the Docker daemon. Is Docker running?" >&2
  exit 1
fi

# Export .env so this script can use POSTGRES_USER/POSTGRES_DB in the health command.
set -a
# shellcheck disable=SC1091
source .env
set +a
SERVER_NAME=${SERVER_NAME:-shoplite.test}

log() { printf '\n==> %s\n' "$*"; }

# Containers started by this run, last one first, for the rollback below.
started=()
rollback() {
  echo "error: startup failed; removing the containers this run started" >&2
  ((${#started[@]})) && docker rm -f "${started[@]}" >/dev/null 2>&1 || true
  echo "       nothing was left running; fix the error above and run ./scripts/up.sh again" >&2
}


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

# Make sure every image exists before touching the host: build it from the
# checkout, or pull it when REGISTRY is set.
ensure_images() {
  local svc dir image

  for svc in frontend catalog inventory orders; do
    case $svc in
      frontend)  dir=frontend ;;
      *)         dir="$svc-service" ;;
    esac
    image="${IMAGE_PREFIX}shop-$svc:$TAG"

    if docker image inspect "$image" >/dev/null 2>&1; then
      echo "    $image"
      continue
    fi

    if [[ -n $REGISTRY ]]; then
      echo "    pulling $image"
      docker pull "$image"
    else
      echo "    building $image (first run only, this takes a few minutes)"
      if ! docker build -t "$image" "$dir"; then
        echo "error: build of $image failed; nothing has been started." >&2
        exit 1
      fi
    fi
  done
}

log "Images (using local ones, building or pulling anything missing)"
ensure_images

# From here on, a failed start must not leave a half-up stack.
trap rollback ERR


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
started+=(postgres)
wait_healthy postgres

log "Backends (backend-net, then attached to frontend-net)"
for service in catalog inventory orders; do
  replace "$service"
  docker run -d \
    --name "$service" \
    --network backend-net \
    --restart unless-stopped \
    --env-file .env \
    "${IMAGE_PREFIX}shop-$service:$TAG" >/dev/null
  docker network connect frontend-net "$service"
  started+=("$service")
  wait_healthy "$service"
done

# On a cloud VM, nginx has to answer for the address people actually type.
# No-op on a laptop: the metadata service is unreachable there.
public_ip=""
imds_token=$(curl -fsS --max-time 2 -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null || true)
if [[ -n $imds_token ]]; then
  public_ip=$(curl -fsS --max-time 2 -H "X-aws-ec2-metadata-token: $imds_token" \
    http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || true)
fi

log "Frontend (frontend-net only, the only published port)"
replace frontend
docker run -d \
  --name frontend \
  --network frontend-net \
  --restart unless-stopped \
  --env-file .env \
  -e SERVER_ALIASES="$public_ip" \
  -p 80:80 \
  "${IMAGE_PREFIX}shop-frontend:$TAG" >/dev/null
started+=(frontend)
wait_healthy frontend

trap - ERR

cat <<EOF

ShopLite is up (TAG=$TAG).

  Frontend:  http://${SERVER_NAME}
EOF
if [[ -n $public_ip ]]; then
  echo "             http://${public_ip}"
  echo
  echo "  If that address does not load, open port 80 in the instance's security group."
fi
cat <<EOF
  Backends:  private; reachable only from frontend-net and backend-net.

Locally, add the name to /etc/hosts once, if you haven't:
  127.0.0.1 ${SERVER_NAME}

Stop it with ./scripts/down.sh
EOF
