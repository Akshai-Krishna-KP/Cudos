#!/usr/bin/env bash
# fetch-keyring.sh: download NVIDIA's cuda-keyring .deb for Debian 13, verify the
# pinned SHA256 and key fingerprint, extract the apt keyring to cache/nvidia-debian13/.
# Usage: build/nvidia/fetch-keyring.sh   (runs on the build host)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
source "$REPO/build/versions.env"
D="$REPO/cache/nvidia-debian13"; mkdir -p "$D"; cd "$D"
[[ -f cuda-keyring_1.1-1_all.deb ]] || curl -fsSL -o cuda-keyring_1.1-1_all.deb "$NVIDIA_DEBIAN_REPO_URL/cuda-keyring_1.1-1_all.deb"
echo "$CUDA_KEYRING_DEBIAN13_SHA256  cuda-keyring_1.1-1_all.deb" | sha256sum -c --quiet -
bsdtar -xOf cuda-keyring_1.1-1_all.deb 'data.tar*' | bsdtar -xOf - ./usr/share/keyrings/cuda-archive-keyring.gpg > cuda-archive-keyring.gpg
gpg --show-keys --with-colons cuda-archive-keyring.gpg | grep -q "^fpr:::::::::$CUDA_KEYRING_DEBIAN13_FPR:" \
  || { echo "keyring fingerprint mismatch" >&2; exit 1; }
echo "keyring ok: $D/cuda-archive-keyring.gpg"
