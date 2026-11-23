#!/usr/bin/env bash
# Stops and removes the stack. Keeps the pgdata volume unless --purge is given.
# Usage: ./scripts/down.sh [--purge]
set -euo pipefail

for name in frontend orders inventory catalog postgres; do
  docker rm -f "$name" >/dev/null 2>&1 && echo "removed $name" || true
done

for net in frontend-net backend-net; do
  docker network rm "$net" >/dev/null 2>&1 && echo "removed network $net" || true
done

if [ "${1:-}" = "--purge" ]; then
  docker volume rm pgdata >/dev/null 2>&1 && echo "removed volume pgdata" || true
else
  echo "Kept volume pgdata (use --purge to delete data)"
fi
