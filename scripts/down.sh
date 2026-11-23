#!/usr/bin/env bash
# ShopLite Phase 1: stop and remove containers and networks.
#
#   ./scripts/down.sh            # keeps the pgdata volume (data survives)
#   ./scripts/down.sh --purge    # removes the volume too (fresh seed next start)
set -euo pipefail

cd "$(dirname "$0")/.."

purge=false
for arg in "$@"; do
  case $arg in
    --purge) purge=true ;;
    *) echo "usage: $0 [--purge]" >&2; exit 2 ;;
  esac
done

echo "Removing containers"
# The frontend first so it stops accepting requests while the rest shut down.
docker rm -f frontend orders inventory catalog postgres >/dev/null 2>&1 || true

echo "Removing networks"
docker network rm frontend-net backend-net >/dev/null 2>&1 || true

if $purge; then
  echo "Removing pgdata volume (all data will be lost)"
  docker volume rm pgdata >/dev/null 2>&1 || true
else
  echo "Keeping pgdata volume (use --purge to delete it)"
fi
