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
BIN="watchtower"
BUILDER="watchtower-builder"

for cmd in git docker go; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "error: missing required command: $cmd" >&2
    exit 1
  }
done

if [[ ! -f "go.mod" || ! -f "dockerfiles/Dockerfile" ]]; then
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
  local goos="$1"
  local goarch="$2"
  local platform="$3"
  local image_tag="$4"
  local extra_goenv="${5:-}"

  rm -f "$BIN"
  env GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=0 $extra_goenv \
    go build -ldflags "-s -w -X github.com/containrrr/watchtower/internal/meta.Version=${TAG}" \
    -o "$BIN" .

  docker buildx build \
    --platform "$platform" \
    -f dockerfiles/Dockerfile \
    -t "${REGISTRY}:${image_tag}" \
    --push .
}

build_and_push linux amd64 linux/amd64 "amd64-${VER}"
build_and_push linux 386 linux/386 "i386-${VER}"
build_and_push linux arm linux/arm/v6 "armhf-${VER}" "GOARM=6"
build_and_push linux arm64 linux/arm64/v8 "arm64v8-${VER}"

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

rm -f "$BIN"
