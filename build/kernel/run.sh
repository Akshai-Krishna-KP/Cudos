#!/usr/bin/env bash
# run.sh: build the kernel builder image if needed and run build-kernel.sh in it.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/build/versions.env"
TAG="localhost/trackc-kernel-builder:${DEBIAN_SNAPSHOT,,}"
podman image exists "$TAG" || podman build -t "$TAG" -f "$REPO/build/kernel/Containerfile.kernel" \
  --build-arg BUILDER_BASE_IMAGE="$BUILDER_BASE_IMAGE" --build-arg DEBIAN_SNAPSHOT="$DEBIAN_SNAPSHOT" \
  --build-arg DEBIAN_SUITE="$DEBIAN_SUITE" "$REPO/build/kernel"
exec podman run --rm -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" -v "$REPO:/src:z" "$TAG" bash /src/build/kernel/build-kernel.sh
