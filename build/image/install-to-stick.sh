#!/usr/bin/env bash
# install-to-stick.sh: put a built image onto the 64 GB stick WHILE THE STICK IS
# RUNNING THE BASELINE on the target laptop (driven over SSH from Laptop 1).
#   - creates p3 trackc-root (8 GiB, squashfs) and p4 trackc-persist (rest, ext4
#     TRACKC_PERSIST) in the free space after the baseline (first run only)
#   - writes the squashfs to p3 (verified by SHA256), the UKI to ESP:/EFI/trackc/
#   - adds a GRUB menu entry "trackc" to the baseline's GRUB (chainloads the UKI)
# Usage: build/image/install-to-stick.sh <host> <variant> [--wipe-persist]
# Safety: the target disk is found by the stick's USB serial on the target and
# must be the USB disk the running baseline root lives on.
set -euo pipefail
# User on the target: "lazarus" on the appliance, "trackc" on the stock Ubuntu baseline.
pick_user() { for u in lazarus trackc; do ssh -i "$HOME/.ssh/trackc_ed25519" -o BatchMode=yes -o ConnectTimeout=6 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error "$u@$1" true 2>/dev/null && { echo "$u"; return; }; done; echo trackc; }
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOST=${1:?host}; VARIANT=${2:?variant}; WIPE=${3:-}
O="$REPO/out/$VARIANT"
SERIAL=03018820042024224003
S=(ssh -i "$HOME/.ssh/trackc_ed25519" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=error "$(pick_user "$HOST")@$HOST")  # lab LAN: baseline and appliance alternate on the same IPs
[[ -f $O/rootfs.squashfs && -f $O/trackc.efi ]] || { echo "build $VARIANT first" >&2; exit 1; }

"${S[@]}" sudo bash -s "$SERIAL" "$WIPE" <<'REMOTE_PART'
set -euo pipefail
SERIAL=$1; WIPE=${2:-}
D=$(readlink -f "/dev/disk/by-id/usb-SanDisk_Cruzer_Blade_${SERIAL}-0:0")
root=$(findmnt -no SOURCE /)
[[ $(lsblk -no PKNAME "$root") == "${D#/dev/}" && $(lsblk -dno TRAN "$D") == usb ]] \
  || { echo "refusing: $D is not the USB stick holding the running root" >&2; exit 1; }
[[ $(findmnt -no FSTYPE /) == squashfs ]] && { echo "refusing: running the custom image itself; boot the baseline first" >&2; exit 1; }
if [[ ! -e /dev/disk/by-partlabel/trackc-root ]]; then
  echo "creating p3 trackc-root (8 GiB) and p4 trackc-persist on $D"
  sgdisk -n 3:0:+8G -t 3:8300 -c 3:trackc-root -n 4:0:0 -t 4:8300 -c 4:trackc-persist "$D"
  partx -a "$D" 2>/dev/null || partx -u "$D"
  udevadm settle
  WIPE=--wipe-persist
fi
P4=$(readlink -f /dev/disk/by-partlabel/trackc-persist)
if [[ $WIPE == --wipe-persist ]]; then
  mkfs.ext4 -q -F -L TRACKC_PERSIST "$P4"; echo "persist formatted: $P4"
fi
lsblk -o NAME,SIZE,PARTLABEL,LABEL,FSTYPE "$D"
REMOTE_PART

size=$(stat -c %s "$O/rootfs.squashfs")
echo "writing squashfs ($((size / 1048576)) MiB) to p3..."
"${S[@]}" 'sudo dd of=/dev/disk/by-partlabel/trackc-root bs=4M oflag=direct status=none && sync' < "$O/rootfs.squashfs"
remote=$("${S[@]}" "sudo head -c $size /dev/disk/by-partlabel/trackc-root | sha256sum" | awk '{print $1}')
local_sha=$(sha256sum < "$O/rootfs.squashfs" | awk '{print $1}')
[[ $remote == "$local_sha" ]] && echo "squashfs verified on stick ($local_sha)" \
  || { echo "squashfs hash MISMATCH" >&2; exit 1; }

"${S[@]}" 'sudo install -d /boot/efi/EFI/trackc && sudo tee /boot/efi/EFI/trackc/trackc.efi >/dev/null' < "$O/trackc.efi"
"${S[@]}" sudo bash -s <<'REMOTE_GRUB'
set -euo pipefail
uuid=$(findmnt -no UUID /boot/efi)
{
  echo '#!/bin/sh'
  echo "cat <<'GRUBCFG'"
  echo "menuentry 'Track C GPU appliance' --id trackc {"
  echo '  insmod part_gpt'
  echo '  insmod fat'
  echo '  insmod chain'
  echo "  search --no-floppy --fs-uuid --set=root $uuid"
  echo '  chainloader /EFI/trackc/trackc.efi'
  echo '}'
  echo 'GRUBCFG'
} > /etc/grub.d/41_trackc
chmod 755 /etc/grub.d/41_trackc
grep -q '^GRUB_DEFAULT=saved' /etc/default/grub || sed -i 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved/' /etc/default/grub
update-grub 2>&1 | tail -2
grep -c "menuentry 'Track C GPU appliance'" /boot/grub/grub.cfg
REMOTE_GRUB
echo "installed. Boot it once:  build/image/set-boot.sh $HOST once-trackc, then reboot"
