#!/usr/bin/env bash
# image-size.sh: the image-size numbers required by the report for a built variant:
# uncompressed rootfs (du at build time, /boot excluded), compressed squashfs, UKI,
# total on the medium (UKI + squashfs; the preloaded container image is inside the
# squashfs as an OCI archive), the container image itself, and the dpkg package count.
# Source data: out/<variant>/sizes.txt + packages.tsv written by the build.
# Usage: measure/image-size.sh <release|dev>   Output: docs/results/phase8/size-<variant>.txt
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; V=${1:?variant}
S="$REPO/out/$V/sizes.txt"; P="$REPO/out/$V/packages.tsv"
[[ -f $P ]] || P="$REPO/out/rootfs-$V-packages.tsv"
OUT="$REPO/docs/results/phase8/size-$V.txt"; mkdir -p "${OUT%/*}"
# shellcheck disable=SC1090
source <(grep -E '^[a-z_]+=[0-9]+$' "$S")
mib() { awk "BEGIN{printf \"%.1f\", $1/1048576}"; }
{
  echo "# image-size $V  $(date -Is)  git=$(git -C "$REPO" rev-parse --short HEAD)"
  echo "rootfs_uncompressed_MiB=$(mib "$rootfs_uncompressed_bytes")"
  echo "squashfs_MiB=$(mib "$squashfs_bytes")"
  echo "uki_MiB=$(mib "$uki_bytes")   # kernel+initrd+cmdline on the ESP"
  echo "medium_total_MiB=$(mib $((squashfs_bytes + uki_bytes)))   # UKI + squashfs (container archive included)"
  echo "bench_container_archive_MiB=$(mib "$bench_image_tar_bytes")   # inside the squashfs"
  echo "dpkg_packages=$(wc -l < "$P")"
  echo "non_dpkg_components=nvidia open kernel modules (5 .ko), nvidia-smi binary, trackc-bench OCI archive"
} | tee "$OUT"
