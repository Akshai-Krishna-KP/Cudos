#!/usr/bin/env bash
# build-rootfs.sh: bootstrap the Debian minbase root filesystem from the pinned
# snapshot and apply overlay/rootfs. Runs INSIDE the builder container.
# Usage: build/builder.sh build/rootfs/build-rootfs.sh
# Output: /src/out/rootfs/ (directory tree)
#
# mmdebstrap is used instead of plain debootstrap: same Debian bootstrap
# (--variant=minbase), but it works inside a rootless container (no mknod),
# honours SOURCE_DATE_EPOCH, and cleans apt caches for a smaller image.
set -euo pipefail
SRC=/src
source "$SRC/build/versions.env"
OUT="$SRC/out/rootfs"
rm -rf "$OUT"; mkdir -p "$OUT"

PKGS=$(sed -e 's/#.*//' -e '/^\s*$/d' "$SRC/build/rootfs/packages.txt" | awk '{print $1}' | paste -sd,)

mmdebstrap \
  --variant=minbase \
  --mode=root \
  --include="$PKGS" \
  --aptopt='Acquire::Check-Valid-Until "false"' \
  --aptopt='Acquire::Retries "5"' \
  --aptopt='APT::Install-Recommends "false"' \
  --dpkgopt='path-exclude=/usr/share/man/*' \
  --dpkgopt='path-exclude=/usr/share/info/*' \
  --dpkgopt='path-exclude=/usr/share/locale/*' \
  --dpkgopt='path-exclude=/usr/share/doc/*' \
  --dpkgopt='path-include=/usr/share/doc/*/copyright' \
  --setup-hook='mkdir -p "$1/etc/initramfs-tools" && cp -a '"$SRC"'/overlay/rootfs/etc/initramfs-tools/. "$1/etc/initramfs-tools/"' \
  --customize-hook='cp -a '"$SRC"'/overlay/rootfs/. "$1/"' \
  --customize-hook='chroot "$1" update-initramfs -u -k all' \
  --customize-hook='rm -f "$1/etc/machine-id" && touch "$1/etc/machine-id"' \
  --customize-hook='rm -rf "$1/var/log/"*.log "$1/var/cache/debconf/"*-old "$1/var/lib/dpkg/"*-old' \
  "$DEBIAN_SUITE" "$OUT" \
  "deb $DEBIAN_MIRROR $DEBIAN_SUITE main" \
  "deb $DEBIAN_MIRROR $DEBIAN_SUITE-updates main" \
  "deb $DEBIAN_SECURITY_MIRROR $DEBIAN_SUITE-security main"

chroot "$OUT" dpkg-query -W -f='${Package}\t${Version}\n' > "$SRC/out/rootfs-packages.tsv"
echo "rootfs: $(du -sh "$OUT" | cut -f1), $(wc -l < "$SRC/out/rootfs-packages.tsv") packages"
