#!/usr/bin/env bash
set -euo pipefail

: "${IMAGE_TAG:?Set IMAGE_TAG to the commit SHA}"
: "${AWS_REGION:?Set AWS_REGION}"
: "${ECR_REPOSITORY_URI:?Set ECR_REPOSITORY_URI}"
: "${SERVICE_LIST:?Set SERVICE_LIST}"

REGISTRY="${ECR_REPOSITORY_URI%%/*}"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

for SERVICE in $SERVICE_LIST; do
  case "$SERVICE" in
    frontend) CONTEXT="frontend" ;;
    catalog) CONTEXT="catalog-service" ;;
    inventory) CONTEXT="inventory-service" ;;
    orders) CONTEXT="order-service" ;;
    *) echo "Unknown service: $SERVICE"; exit 1 ;;
  esac

  IMAGE="${ECR_REPOSITORY_URI}:${SERVICE}-${IMAGE_TAG}"

  echo "Building $IMAGE"
  docker build --platform linux/amd64 -t "$IMAGE" "$CONTEXT"

  echo "Pushing $IMAGE"
  docker push "$IMAGE"
done
