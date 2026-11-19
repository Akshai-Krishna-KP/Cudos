#!/usr/bin/env bash
# qemu-smoke.sh: Phase 2 gate. Boots out/disk.img under QEMU/KVM with UEFI
# (OVMF) twice, on a scratch COPY of the image, and checks the serial console:
#   - firmware boots the UKI, kernel + initramfs mount squashfs + overlays
#   - trackc-selftest reports RESULT PASS (read-only root, mount flags)
#   - a login prompt appears
#   - boot 2 sees boot-count 2 (writable state persisted on the persist partition)
# Usage: test/qemu-smoke.sh [disk.img]     Logs: docs/results/phase2/
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMG="${1:-$REPO/out/disk.img}"
RES="$REPO/docs/results/phase2"; mkdir -p "$RES"
WORK=$(mktemp -d "$REPO/out/smoke.XXXX"); trap 'rm -rf "$WORK"' EXIT
cp --sparse=always "$IMG" "$WORK/disk.img"
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$WORK/vars.fd"
TIMEOUT=${TIMEOUT:-180}

boot() {  # boot <n>: run until login prompt + selftest result, or timeout
  local n=$1 log="$RES/qemu-boot$1.log"; : > "$log"
  qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 2 -m 2G \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file="$WORK/vars.fd" \
    -drive file="$WORK/disk.img",format=raw,if=virtio \
    -display none -serial file:"$log" -no-reboot -nic none &
  local qpid=$! t=0
  while (( t < TIMEOUT )); do
    if grep -q "TRACKC-SELFTEST RESULT" "$log" && grep -qE "login:" "$log"; then break; fi
    kill -0 $qpid 2>/dev/null || break
    sleep 1; t=$((t+1))
  done
  sleep 2; kill $qpid 2>/dev/null || true; wait $qpid 2>/dev/null || true
  echo "boot $n: ${t}s to login prompt + selftest"
}

boot 1; boot 2
fail=0
for n in 1 2; do
  L="$RES/qemu-boot$n.log"
  grep -q "TRACKC-SELFTEST RESULT PASS" "$L" && echo "boot $n selftest: PASS" || { echo "boot $n selftest: FAIL"; fail=1; }
  grep -q "login:" "$L" && echo "boot $n login prompt: yes" || { echo "boot $n login prompt: NO"; fail=1; }
done
grep -q "TRACKC-SELFTEST boot-count 2" "$RES/qemu-boot2.log" && echo "persistence across reboot: PASS" || { echo "persistence across reboot: FAIL"; fail=1; }
grep -a "TRACKC-SELFTEST" "$RES/qemu-boot2.log" | tr -d '\r' > "$RES/selftest-boot2.txt" || true
{ echo "# $(date -Is) image=$(basename "$IMG") sha256=$(sha256sum "$IMG" | cut -d' ' -f1)"; echo "fail=$fail"; } > "$RES/smoke-summary.txt"
exit $fail
