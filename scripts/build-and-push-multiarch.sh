#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-and-push-multiarch.sh <tag> [registry]

Examples:
  ./scripts/build-and-push-multiarch.sh v1.0.0
  ./scripts/build-and-push-multiarch.sh v1.0.0 registry.xaas.ar/watchtower
EOF
}

if [[ "${1:-}" == "" || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

TAG="$1"
REGISTRY="${2:-registry.xaas.ar/watchtower}"
VER="${TAG#v}"
BUILDER="watchtower-builder"

for cmd in git docker; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "error: missing required command: $cmd" >&2
    exit 1
  }
done

if [[ ! -f "dockerfiles/Dockerfile.dev-self-contained" ]]; then
  echo "error: run this from the watchtower repository root" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: git working tree is dirty; commit or stash changes before building" >&2
  exit 1
fi

docker login registry.xaas.ar
docker buildx create --use --name "$BUILDER" >/dev/null 2>&1 || true
docker buildx inspect --bootstrap >/dev/null

build_and_push() {
  local platform="$1"
  local image_tag="$2"
  local version_arg="${3:-$TAG}"

  docker buildx build \
    --platform "$platform" \
    --build-arg "WATCHTOWER_VERSION=${version_arg}" \
    -f dockerfiles/Dockerfile.dev-self-contained \
    -t "${REGISTRY}:${image_tag}" \
    --push .
}

build_and_push linux/amd64 "amd64-${VER}"
build_and_push linux/386 "i386-${VER}"
build_and_push linux/arm/v6 "armhf-${VER}"
build_and_push linux/arm64/v8 "arm64v8-${VER}"

docker manifest create "${REGISTRY}:${VER}" \
  "${REGISTRY}:amd64-${VER}" \
  "${REGISTRY}:i386-${VER}" \
  "${REGISTRY}:armhf-${VER}" \
  "${REGISTRY}:arm64v8-${VER}"

docker manifest annotate "${REGISTRY}:${VER}" "${REGISTRY}:i386-${VER}" --os linux --arch 386
docker manifest annotate "${REGISTRY}:${VER}" "${REGISTRY}:armhf-${VER}" --os linux --arch arm
docker manifest annotate "${REGISTRY}:${VER}" "${REGISTRY}:arm64v8-${VER}" --os linux --arch arm64 --variant v8
docker manifest push "${REGISTRY}:${VER}"

docker manifest create "${REGISTRY}:latest" \
  "${REGISTRY}:amd64-${VER}" \
  "${REGISTRY}:i386-${VER}" \
  "${REGISTRY}:armhf-${VER}" \
  "${REGISTRY}:arm64v8-${VER}"

docker manifest annotate "${REGISTRY}:latest" "${REGISTRY}:i386-${VER}" --os linux --arch 386
docker manifest annotate "${REGISTRY}:latest" "${REGISTRY}:armhf-${VER}" --os linux --arch arm
docker manifest annotate "${REGISTRY}:latest" "${REGISTRY}:arm64v8-${VER}" --os linux --arch arm64 --variant v8
docker manifest push "${REGISTRY}:latest"
