#!/usr/bin/env bash
# prefetch-debs.sh: download every .deb the baseline's late-commands need
# (NVIDIA stack + lab remote access) on the HOST, into cache/debs/, using an
# Ubuntu 24.04 container with the same NVIDIA repo. The installer VM then gets
# them over its local link instead of the (slow, flaky) hotspot.
# apt re-verifies every .deb against the signed repo indexes inside the VM, so
# this is only a cache, not a trust change. Safe to re-run: existing files are
# reused, partial downloads resume.
# Usage: baseline/prefetch-debs.sh
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO/build/versions.env"
mkdir -p "$REPO/cache/debs"
PKGS="linux-headers-generic curl ca-certificates build-essential
  nvidia-open=${NVIDIA_DRIVER_VERSION}-1ubuntu1 $CUDA_TOOLKIT_PKG $CUDNN_PKG
  nvidia-container-toolkit=${NVIDIA_CTK_VERSION} nvidia-container-toolkit-base=${NVIDIA_CTK_VERSION}
  libnvidia-container-tools=${NVIDIA_CTK_VERSION} libnvidia-container1=${NVIDIA_CTK_VERSION} podman
  openssh-server wpasupplicant linux-firmware wireless-regdb iw avahi-daemon"
podman run --rm -v "$REPO/cache/debs:/debs:z" docker.io/library/ubuntu:24.04 bash -euo pipefail -c "
  export DEBIAN_FRONTEND=noninteractive
  A='-o Acquire::Retries=20 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Dir::Cache::archives=/debs'
  apt-get \$A update -qq
  apt-get \$A install -y -qq --no-install-recommends curl ca-certificates >/dev/null
  curl -fsSL --retry 10 -o /tmp/k.deb '$NVIDIA_REPO_URL/$CUDA_KEYRING_DEB' && dpkg -i /tmp/k.deb >/dev/null
  apt-get \$A update -qq
  apt-get \$A install -y --download-only $(echo $PKGS)
"
echo "cache/debs: $(ls "$REPO/cache/debs"/*.deb | wc -l) debs, $(du -sh "$REPO/cache/debs" | cut -f1)"
