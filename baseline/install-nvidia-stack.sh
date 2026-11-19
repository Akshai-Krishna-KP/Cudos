#!/usr/bin/env bash
# install-nvidia-stack.sh: installs the "identical functionality" NVIDIA stack
# on the stock Ubuntu baseline: open driver (DKMS), full CUDA toolkit, cuDNN,
# NVIDIA Container Toolkit, Podman. Versions come from build/versions.env.
# Runs inside the installed target (curtin in-target) during autoinstall,
# but also works on a running baseline: sudo ./install-nvidia-stack.sh <dir-with-versions.env>
set -euo pipefail
SRC="${1:-/root/trackc}"
# shellcheck source=../build/versions.env
source "$SRC/versions.env"
export DEBIAN_FRONTEND=noninteractive
APT="apt-get -y -o Dpkg::Options::=--force-confold -o DPkg::Options::=--force-unsafe-io"

# Kernel headers for every installed kernel so DKMS can build the open modules.
$APT install linux-headers-generic curl ca-certificates build-essential
for k in /lib/modules/*; do $APT install "linux-headers-$(basename "$k")" || true; done

curl -fsSL -o /tmp/cuda-keyring.deb "$NVIDIA_REPO_URL/$CUDA_KEYRING_DEB"
dpkg -i /tmp/cuda-keyring.deb
apt-get update

# Exact driver version (all nvidia-open deps resolve to the same branch).
$APT install "nvidia-open=${NVIDIA_DRIVER_VERSION}-1ubuntu1"
$APT install "$CUDA_TOOLKIT_PKG" "$CUDNN_PKG" \
  "nvidia-container-toolkit=${NVIDIA_CTK_VERSION}" \
  "nvidia-container-toolkit-base=${NVIDIA_CTK_VERSION}" \
  "libnvidia-container-tools=${NVIDIA_CTK_VERSION}" \
  "libnvidia-container1=${NVIDIA_CTK_VERSION}" \
  podman
apt-mark hold nvidia-open "$CUDA_TOOLKIT_PKG" nvidia-container-toolkit >/dev/null

# DKMS status for the record (build happens per installed kernel).
dkms status || true
echo "install-nvidia-stack: done"
