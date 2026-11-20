#!/usr/bin/env bash
# build-bench-image.sh: build the slim CUDA benchmark container on the build host
# (rootless Podman, no network: compiler + CUDA come from the prefetched debs) and
# export it to out/trackc-bench.tar, which the image build copies into the rootfs.
# Usage: build/container/build-bench-image.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/build/versions.env"
ctx=$(mktemp -d); trap 'rm -rf "$ctx"' EXIT
cp "$REPO/build/container/Containerfile.bench" "$REPO/benchmark/src/trackc_bench.cu" "$ctx/"
podman build --network=none --build-arg BASE="$CUDA_CONTAINER_BASE" \
  -v "$REPO/cache/debs:/debs:ro,z" -t "$BENCH_IMAGE" -f "$ctx/Containerfile.bench" "$ctx"
mkdir -p "$REPO/out"; rm -f "$REPO/out/trackc-bench.tar"
podman save --format oci-archive -o "$REPO/out/trackc-bench.tar" "$BENCH_IMAGE"
podman image inspect "$BENCH_IMAGE" --format 'image {{.Id}} size {{.Size}}'
ls -l "$REPO/out/trackc-bench.tar"
