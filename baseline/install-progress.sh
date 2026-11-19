#!/usr/bin/env bash
# install-progress.sh: live progress bar for install-baseline-qemu.sh.
# Reads the installer's serial log (cache/qemu-install.log) for stage markers
# and the QEMU process's write counter for data written into the guest disk.
# The percentage is an ESTIMATE (stage weights + expected ~14 GiB during the
# NVIDIA/CUDA step); the stage name and GiB counters are exact.
# Usage: baseline/install-progress.sh      (Ctrl-C to quit; does not affect the install)
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$REPO/cache/qemu-install.log"
LATE_EXPECTED_GIB=14
# marker in log | percent when reached | label
STAGES=(
  "start: +subiquity/Install/install:|5|Installer booted, config loaded"
  "start: +subiquity/.*/stage-partitioning:|8|Partitioning the USB stick"
  "start: +subiquity/.*/stage-extract:|12|Copying Ubuntu onto the stick"
  "start: +subiquity/.*/stage-curthooks:|22|Configuring system, kernel, bootloader"
  "start: +subiquity/Install/install/postinstall:|35|Installing security updates"
  "start: +subiquity/Late/run|45|NVIDIA driver + CUDA + cuDNN + Podman + SSH"
  "reboot: Power down|97|Installer finished, VM powering off"
)
late_base=""
bar() { local p=$1 w=40 f; f=$((p*w/100)); printf '[%s%s] %3d%%' "$(printf '#%.0s' $(seq 1 $f) 2>/dev/null)" "$(printf '.%.0s' $(seq 1 $((w-f))) 2>/dev/null)" "$p"; }
while :; do
  [[ -f $LOG ]] || { printf '\rwaiting for installer log...'; sleep 2; continue; }
  pct=0; label="Starting VM"
  for s in "${STAGES[@]}"; do
    IFS='|' read -r m p l <<<"$s"
    if tr -d '\r' < "$LOG" | grep -aqE -- "$m"; then pct=$p; label=$l; fi
  done
  # current sub-step (last "start:" line), e.g. "installing kernel"
  sub=$(tr -d '\r' < "$LOG" | grep -a '^start:' | grep -v status_GET | tail -1 | sed 's/.*: //' | cut -c1-40)
  [[ -n $sub ]] && label="$label > $sub"
  qpid=$(pgrep -f "qemu-system-x86_64 -machine.*TRACKC64" | head -1)
  if [[ -n $qpid ]]; then
    wbytes=$(awk '/^wchar:/{print $2}' "/proc/$qpid/io" 2>/dev/null || echo 0)
    if [[ $pct -eq 45 ]]; then
      [[ -n $late_base ]] || late_base=$wbytes
      extra=$(( (wbytes - late_base) * 50 / (LATE_EXPECTED_GIB * 1073741824) ))
      (( extra > 50 )) && extra=50; pct=$((45 + extra))
    fi
  else
    if [[ $pct -ge 97 ]]; then pct=100; label="Done (flushing/finished, see cache/install-baseline.out)"
    elif [[ $pct -gt 0 ]]; then label="VM not running: check cache/install-baseline.out"; fi
    wbytes=0
  fi
  usb=$(awk '$3=="sda"{printf "%.2f", $10*512/1073741824}' /proc/diskstats)
  el=$(ps -o etimes= -p "${qpid:-1}" 2>/dev/null | tr -d " "); [[ -n $qpid ]] || el=0
  printf '\r\033[K%s  %s | VM wrote %.2f GiB | USB flushed %s GiB | %02d:%02d' \
    "$(bar $pct)" "$label" "$(awk "BEGIN{print $wbytes/1073741824}")" "$usb" $((el/60)) $((el%60))
  [[ $pct -eq 100 ]] && { echo; exit 0; }
  sleep 2
done
