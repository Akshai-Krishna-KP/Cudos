#!/usr/bin/env bash
# builder.sh: build (if needed) the pinned builder image and run a command in it.
# The repo is mounted at /src, outputs go to /src/out (gitignored).
# --privileged is needed so mmdebstrap can mount /proc etc. inside the chroot;
# with rootless Podman this is still confined to the user namespace.
# Usage: build/builder.sh <command...>     e.g. build/builder.sh build/rootfs/build-rootfs.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO/build/versions.env"
TAG="localhost/trackc-builder:${DEBIAN_SNAPSHOT,,}"
if ! podman image exists "$TAG"; then
  podman build -t "$TAG" -f "$REPO/build/Containerfile.builder" \
    --build-arg BUILDER_BASE_IMAGE="$BUILDER_BASE_IMAGE" \
    --build-arg DEBIAN_SNAPSHOT="$DEBIAN_SNAPSHOT" \
    --build-arg DEBIAN_SUITE="$DEBIAN_SUITE" "$REPO/build"
fi
mkdir -p "$REPO/out"
exec podman run --rm --privileged --network=host \
  -e SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
  -v "$REPO:/src:z" "$TAG" "$@"
