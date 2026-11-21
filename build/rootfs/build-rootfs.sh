#!/usr/bin/env bash
# build-rootfs.sh: bootstrap the Debian 13 minbase root filesystem from the pinned
# snapshot, add the NVIDIA driver (open kernel modules built here, compilers then
# removed), Podman + the preloaded CUDA benchmark image, hardening and services.
# Runs INSIDE the builder container.
#
# Usage: build/builder.sh build/rootfs/build-rootfs.sh [release|dev]
#   release: the graded appliance (no network services, no login users)
#   dev:     + lab remote access (SSH key-only, hotspot Wi-Fi, NOPASSWD sudo);
#            needs cache/wifi.env and out/dev-secrets/authorized_keys (not in Git)
# Needs:   out/trackc-bench.tar (build/container/build-bench-image.sh),
#          cache/nvidia-debian13/cuda-archive-keyring.gpg (build/nvidia/fetch-keyring.sh)
# Output:  /src/out/rootfs-<variant>/ (directory tree), out/rootfs-<variant>-packages.tsv
#
# mmdebstrap is used instead of plain debootstrap: same Debian bootstrap
# (--variant=minbase), but it works inside a rootless container (no mknod),
# honours SOURCE_DATE_EPOCH, and cleans apt caches for a smaller image.
set -euo pipefail
SRC=/src
VARIANT=${1:-release}
KERNEL=${2:-debian}   # debian = Debian linux-image-amd64; debian-iso = same + live-ISO initramfs; trackc = our kernel (out/kernel); trackc-iso = live-ISO kernel (out/kernel-iso)
KDIR=$SRC/out/kernel; [[ $KERNEL == trackc-iso ]] && KDIR=$SRC/out/kernel-iso
source "$SRC/build/versions.env"
OUT="$SRC/out/rootfs-$VARIANT"
KEYRING=/usr/share/keyrings/cuda-archive-keyring.gpg
[[ -f $SRC/out/trackc-bench.tar ]] || { echo "missing out/trackc-bench.tar" >&2; exit 1; }
install -m 644 "$SRC/cache/nvidia-debian13/cuda-archive-keyring.gpg" "$KEYRING"
rm -rf "$OUT"; mkdir -p "$OUT" "$SRC/cache/mmdebstrap-debs"
# Downloaded .debs are kept in cache/mmdebstrap-debs (gitignored) so rebuilds work offline;
# apt still verifies every .deb against the signed indexes.

pkgs() { sed -e 's/#.*//' -e '/^\s*$/d' "$@" | awk '{print $1}' | paste -sd,; }
PKGS=$(pkgs "$SRC/build/rootfs/packages.txt")
[[ $VARIANT == dev || $VARIANT == portable ]] && PKGS="$PKGS,$(pkgs "$SRC/build/rootfs/packages-dev.txt")"
# portable: shareable image (no lab secrets); grows its persist partition on first boot.
[[ $VARIANT == portable ]] && PKGS="$PKGS,gdisk,e2fsprogs"
if [[ $KERNEL == trackc* ]]; then
  ls "$KDIR"/linux-image-*-trackc_*.deb >/dev/null || { echo "build the kernel first (build/kernel/run.sh)" >&2; exit 1; }
  PKGS=$(echo "$PKGS" | tr , '\n' | grep -vx linux-image-amd64 | paste -sd,)
fi
V=$NVIDIA_DEB_VERSION; C=$NVIDIA_CTK_DEB_VERSION
# NVIDIA userspace kept in the image: CUDA driver lib, NVML, GSP firmware, CTK (CDI).
# nvidia-powerd = Dynamic Boost: without it the laptop GPU runs ~12% slower (docs/results/phase8/powerd-experiment-baseline.txt).
NV_KEEP="libcuda1=$V,libnvidia-ml1=$V,firmware-nvidia-gsp=$V,nvidia-modprobe=$V,nvidia-powerd=$V"
NV_KEEP="$NV_KEEP,nvidia-container-toolkit=$C,nvidia-container-toolkit-base=$C,libnvidia-container-tools=$C,libnvidia-container1=$C"
# Build-only: compiled/extracted, then purged (modules + nvidia-smi binary are kept).
NV_BUILD="nvidia-kernel-open-dkms=$V,nvidia-driver-cuda=$V,dkms"
[[ $KERNEL == debian* ]] && NV_BUILD="$NV_BUILD,linux-headers-amd64"   # debian-iso: Debian kernel (all drivers, Debian-signed) for the live ISO
# trackc kernel headers run objtool, which links libelf (build-only; autoremoved after).
[[ $KERNEL == trackc* ]] && NV_BUILD="$NV_BUILD,libelf1t64"

mmdebstrap \
  --variant=minbase \
  --mode=root \
  --include="$PKGS,$NV_KEEP,$NV_BUILD" \
  --aptopt='Acquire::Check-Valid-Until "false"' \
  --aptopt='Acquire::Retries "5"' \
  --aptopt='APT::Install-Recommends "false"' \
  --dpkgopt='path-exclude=/usr/share/man/*' \
  --dpkgopt='path-exclude=/usr/share/info/*' \
  --dpkgopt='path-exclude=/usr/share/locale/*' \
  --dpkgopt='path-exclude=/usr/share/doc/*' \
  --dpkgopt='path-include=/usr/share/doc/*/copyright' \
  --setup-hook='mkdir -p "$1/etc/initramfs-tools" "$1/usr/share/keyrings" && cp -a '"$SRC"'/overlay/rootfs/etc/initramfs-tools/. "$1/etc/initramfs-tools/" && cp '"$KEYRING"' "$1'"$KEYRING"'"' \
  --skip=essential/unlink \
  --setup-hook='mkdir -p "$1/var/cache/apt/archives/"' \
  --setup-hook='sync-in '"$SRC"'/cache/mmdebstrap-debs /var/cache/apt/archives/' \
  --customize-hook='sync-out /var/cache/apt/archives '"$SRC"'/cache/mmdebstrap-debs' \
  --customize-hook="$SRC/build/rootfs/customize.sh \"\$1\" $VARIANT $KERNEL" \
  "$DEBIAN_SUITE" "$OUT" \
  "deb http://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT $DEBIAN_SUITE main non-free-firmware" \
  "deb http://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT $DEBIAN_SUITE-updates main non-free-firmware" \
  "deb http://snapshot.debian.org/archive/debian-security/$DEBIAN_SNAPSHOT $DEBIAN_SUITE-security main non-free-firmware" \
  "deb [signed-by=$KEYRING] $NVIDIA_DEBIAN_REPO_URL /"

chroot "$OUT" dpkg-query -W -f='${Package}\t${Version}\n' > "$SRC/out/rootfs-$VARIANT-packages.tsv"
echo "rootfs-$VARIANT: $(du -sh "$OUT" | cut -f1), $(wc -l < "$SRC/out/rootfs-$VARIANT-packages.tsv") packages"
