#!/usr/bin/env bash
# iso-smoke.sh: boot the live ISO in QEMU/KVM (UEFI) as a CD-ROM and as a USB stick;
# pass = self-test RESULT on the serial console + a login prompt. Logs: docs/results/iso/
# Usage: test/iso-smoke.sh [out/iso/trackc-gpu-appliance.iso]
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; ISO=${1:-$REPO/out/iso/trackc-gpu-appliance.iso}
RES=$REPO/docs/results/iso; mkdir -p "$RES"; W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
fail=0
for mode in cdrom usb; do
  cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$W/vars.fd"; L=$RES/qemu-$mode.log; : > "$L"
  if [[ $mode == cdrom ]]; then D=(-cdrom "$ISO")
  else D=(-drive "file=$ISO,format=raw,if=none,id=u,readonly=on" -device qemu-xhci -device usb-storage,drive=u); fi
  qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp 4 -m 6G \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
    -drive if=pflash,format=raw,file="$W/vars.fd" "${D[@]}" \
    -display none -serial file:"$L" -nic none & q=$!
  t=0; while (( t < 180 )); do grep -aq 'TRACKC-SELFTEST RESULT' "$L" && grep -aq 'login:' "$L" && break; sleep 2; t=$((t+2)); done
  kill $q 2>/dev/null; wait $q 2>/dev/null
  r=$(tr -d '\r' < "$L" | grep -ao 'TRACKC-SELFTEST RESULT [A-Z]*' | tail -1)
  echo "$mode: ${t}s, ${r:-no selftest result}, login prompt: $(grep -aq 'login:' "$L" && echo yes || echo NO)"
  [[ $r == *PASS ]] && grep -aq 'login:' "$L" || fail=1
done
exit $fail
