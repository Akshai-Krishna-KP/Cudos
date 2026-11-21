#!/usr/bin/env bash
# set-boot.sh: choose what the 64 GB stick boots, from Laptop 1 over SSH, while the
# target runs EITHER the baseline or the custom image. Edits only the baseline's
# GRUB environment block (/boot/grub/grubenv on the stick's baseline-root
# partition); never touches firmware NVRAM or the laptop's internal disks.
#
# Usage: build/image/set-boot.sh <host> default-trackc|default-baseline|once-trackc|once-baseline
#   default-*  = saved_entry (every boot from now on)
#   once-*     = next_entry (next boot only, then back to the default)
set -euo pipefail
# User on the target: "lazarus" on the appliance, "trackc" on the stock Ubuntu baseline.
pick_user() { for u in lazarus trackc; do ssh -i "$HOME/.ssh/trackc_ed25519" -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error "$u@$1" true 2>/dev/null && { echo "$u"; return; }; done; echo trackc; }
HOST=${1:?host}; MODE=${2:?mode}; TU=$(pick_user "$HOST")
case $MODE in
  default-trackc) KV="saved_entry=trackc" ;;
  default-baseline) KV="saved_entry=0" ;;
  once-trackc) KV="next_entry=trackc" ;;
  once-baseline) KV="next_entry=0" ;;
  *) echo "bad mode $MODE" >&2; exit 1 ;;
esac
ssh -i "$HOME/.ssh/trackc_ed25519" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=error "$TU@$HOST" sudo bash -s "$KV" <<'REMOTE'
set -euo pipefail
KV=$1; key=${KV%%=*}
P=$(readlink -f /dev/disk/by-label/baseline-root)
[[ $(lsblk -no TRAN "/dev/$(lsblk -no PKNAME "$P")") == usb ]] || { echo "baseline-root not on USB" >&2; exit 1; }
if [[ $(findmnt -no SOURCE /) == "$P" ]]; then M=; else M=$(mktemp -d); mount "$P" "$M"; fi
F=$M/boot/grub/grubenv
# Keep other keys, replace ours, rewrite as a 1024-byte GRUB environment block.
body=$( { grep -v -e '^#' -e "^$key=" "$F" 2>/dev/null || true; echo "$KV"; } )
{ printf '# GRUB Environment Block\n%s\n' "$body"; head -c 1024 /dev/zero | tr '\0' '#'; } | head -c 1024 > "$F.new"
mv "$F.new" "$F"; sync
grep -v '^#' "$F"
if [[ -n $M ]]; then umount "$M"; rmdir "$M"; fi
REMOTE
