#!/usr/bin/env bash
# build-cudadev-image.sh: build the CUDA development container used by `cuda-dev` on the
# appliance (offline, from the prefetched debs) and export it to out/trackc-cuda-dev.tar.
# Install onto a running appliance with build/container/install-cudadev.sh <host>.
# Usage: build/container/build-cudadev-image.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/build/versions.env"
ctx=$(mktemp -d); trap 'rm -rf "$ctx"' EXIT
cp "$REPO/build/container/Containerfile.cudadev" "$ctx/"
podman build --network=none --build-arg BASE="$CUDA_CONTAINER_BASE" \
  -v "$REPO/cache/debs:/debs:ro,z" -t "$CUDADEV_IMAGE" -f "$ctx/Containerfile.cudadev" "$ctx"
podman run --rm --network=none "$CUDADEV_IMAGE" sh -c 'nvcc --version | tail -2; g++ --version | head -1'
mkdir -p "$REPO/out"; rm -f "$REPO/out/trackc-cuda-dev.tar"
podman save --format oci-archive -o "$REPO/out/trackc-cuda-dev.tar" "$CUDADEV_IMAGE"
podman image inspect "$CUDADEV_IMAGE" --format 'image {{.Id}} size {{.Size}}'
ls -l "$REPO/out/trackc-cuda-dev.tar"
