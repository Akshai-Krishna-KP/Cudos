#!/usr/bin/env bash
# phase0-prep.sh: one-shot Phase 0 host prep that needs sudo.
#
#   1. Safety-check both USB sticks (must be TRAN=usb and expected size).
#   2. Unmount them and run `f3probe --destructive` on each (ERASES BOTH).
#      Output saved to docs/results/phase0/.
#   3. Download the pinned Ubuntu Server ISO (build/versions.env), verify SHA256.
#   4. Write the ISO to the 8 GB stick (installer for the baseline) and verify.
#
# Usage (run as your normal user from the repo root; it calls sudo itself):
#   baseline/phase0-prep.sh /dev/sda /dev/sdb
#   arg1 = 64 GB dev drive, arg2 = 8 GB installer / release drive
#
# Env:
#   SKIP_F3=1   skip step 1 (e.g. f3probe already done, or the stick's random
#               writes are too slow; the dd + cmp verify still checks the
#               region the ISO occupies).
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../build/versions.env
source "$REPO/build/versions.env"
RESULTS="$REPO/docs/results/phase0"
CACHE="$REPO/cache"
mkdir -p "$RESULTS" "$CACHE"

DEV64="${1:?usage: $0 <64GB-dev> <8GB-dev>}"
DEV8="${2:?usage: $0 <64GB-dev> <8GB-dev>}"

die() { echo "ERROR: $*" >&2; exit 1; }

# check_usb <dev> <min_GiB> <max_GiB>: refuse anything that is not a whole USB disk of the right size
check_usb() {
  local dev=$1 min=$2 max=$3 tran type size_b gib
  [[ -b $dev ]] || die "$dev is not a block device"
  tran=$(lsblk -dno TRAN "$dev"); type=$(lsblk -dno TYPE "$dev")
  size_b=$(lsblk -dbno SIZE "$dev"); gib=$(( size_b / 1024**3 ))
  [[ $type == disk ]] || die "$dev is not a whole disk"
  [[ $tran == usb ]]  || die "$dev is TRAN=$tran, not usb. Refusing."
  (( gib >= min && gib <= max )) || die "$dev is ${gib} GiB, expected ${min}-${max} GiB"
  echo "OK: $dev  $(lsblk -dno SIZE,MODEL,TRAN "$dev")"
}

echo "== Devices =="
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT
check_usb "$DEV64" 50 64
check_usb "$DEV8"  6  8
read -r -p "$DEV8 (and $DEV64 unless SKIP_F3=1) will be COMPLETELY ERASED. Type 'yes' to continue: " ans
[[ $ans == yes ]] || die "aborted"

sudo -v  # ask for the password once up front

unmount_all() {
  local p
  for p in $(lsblk -lno PATH "$1" | tail -n +2); do
    if findmnt -rno TARGET "$p" >/dev/null; then
      udisksctl unmount -b "$p" 2>/dev/null || sudo umount "$p"
    fi
  done
}

echo "== Step 1/3: f3probe (destructive) =="
[[ ${SKIP_F3:-0} == 1 ]] && echo "SKIP_F3=1: skipping f3probe"
for dev in "$DEV64" "$DEV8"; do
  [[ ${SKIP_F3:-0} == 1 ]] && break
  unmount_all "$dev"
  name=$(basename "$dev")
  out="$RESULTS/f3probe-${name}-$(lsblk -dbno SIZE "$dev")B.txt"
  { echo "# $(date -Is)  $(lsblk -dno SIZE,MODEL,SERIAL "$dev")"; \
    sudo f3probe --destructive --time-ops "$dev"; } 2>&1 | tee "$out"
  grep -q "Good news: The device .* is the real thing" "$out" \
    || die "$dev failed f3probe. See $out. Do not use this stick."
done

echo "== Step 2/3: Ubuntu ISO download + verify =="
iso="$CACHE/$UBUNTU_BASELINE_ISO"
if [[ ! -f $iso ]]; then
  curl -fL --retry 3 -C - -o "$iso.part" "$UBUNTU_BASELINE_URL"
  mv "$iso.part" "$iso"
fi
echo "$UBUNTU_BASELINE_SHA256  $iso" | sha256sum -c - || die "ISO checksum mismatch"

echo "== Step 3/3: write ISO to $DEV8 =="
unmount_all "$DEV8"
sudo dd if="$iso" of="$DEV8" bs=4M conv=fsync oflag=direct status=progress
sync
echo "Verifying write..."
sudo cmp -n "$(stat -c %s "$iso")" "$iso" "$DEV8" && echo "Write verified."
{ echo "# $(date -Is)"; echo "iso=$UBUNTU_BASELINE_ISO sha256=$UBUNTU_BASELINE_SHA256 written_to=$DEV8 verified=yes"; } \
  > "$RESULTS/installer-usb.txt"

echo
echo "Done. Results in $RESULTS. The 64 GB stick is now blank; the 8 GB stick is the Ubuntu installer."
