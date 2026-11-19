#!/usr/bin/env bash
# phase0-gate.sh: runs on the baseline at boot on REAL hardware and records the
# Phase 0 gate result (nvidia-smi + CUDA sample) to /var/lib/trackc/.
# Also generates the CDI spec for Podman. If /etc/trackc/auto-poweroff exists,
# powers off when done, so the user only has to boot the stick and wait.
set -uo pipefail
OUT_DIR=/var/lib/trackc; mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/phase0-gate-$(date +%Y%m%dT%H%M%S).txt"
run() { echo "\$ $*"; "$@" 2>&1; echo "[exit $?]"; echo; }
{
  echo "# Phase 0 gate  $(date -Is)  boot_id=$(cat /proc/sys/kernel/random/boot_id)"
  run cat /sys/class/dmi/id/sys_vendor /sys/class/dmi/id/product_name
  run uname -r
  run systemd-detect-virt
  run lspci -nnk -d 10de:
  run lsmod
  run nvidia-smi
  run nvidia-smi --query-gpu=name,driver_version,pstate,temperature.gpu,power.draw --format=csv
  run /opt/trackc/vector_add
  run nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
  run nvidia-ctk cdi list
  run systemd-analyze
  echo "# done $(date -Is)"
} > "$OUT"
ln -sf "$(basename "$OUT")" "$OUT_DIR/phase0-gate-latest.txt"
sync
if [[ -e /etc/trackc/auto-poweroff ]] && [[ $(systemd-detect-virt) == none ]]; then
  sleep 5; systemctl poweroff
fi
