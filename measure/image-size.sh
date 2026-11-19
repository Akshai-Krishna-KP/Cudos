#!/usr/bin/env bash
# image-size.sh: the three image-size numbers required by the report, for the
# current build in out/: uncompressed rootfs (du), compressed squashfs, and
# total used on the medium (ESP content + squashfs; container images added in
# later phases). Usage: measure/image-size.sh [label]   Output: docs/results/size-<label>.txt
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/out"
LABEL="${1:-custom}"; OUT="$REPO/docs/results/size-$LABEL.txt"
# rootfs files are owned by the container's root -> measure inside the userns.
rootfs_kib=$(podman unshare du -sk --exclude=./boot "$O/rootfs" | cut -f1)
sq_b=$(stat -c %s "$O/rootfs.squashfs"); uki_b=$(stat -c %s "$O/trackc.efi")
pkgs=$(wc -l < "$O/rootfs-packages.tsv")
{
  echo "# image-size $LABEL  $(date -Is)  git=$(git -C "$REPO" rev-parse --short HEAD)"
  echo "rootfs_uncompressed_MiB=$(( rootfs_kib / 1024 ))   # du -sk out/rootfs excluding /boot"
  echo "squashfs_MiB=$(awk "BEGIN{printf \"%.1f\", $sq_b/1048576}")"
  echo "uki_MiB=$(awk "BEGIN{printf \"%.1f\", $uki_b/1048576}")   # kernel+initrd+cmdline on ESP"
  echo "medium_used_MiB=$(awk "BEGIN{printf \"%.1f\", ($sq_b+$uki_b)/1048576}")   # squashfs + UKI (no containers yet)"
  echo "dpkg_packages=$pkgs"
} | tee "$OUT"
