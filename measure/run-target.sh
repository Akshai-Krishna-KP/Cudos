#!/usr/bin/env bash
# run-target.sh: run the full measurement series on a target laptop over SSH
# (from Laptop 1) and save raw output to docs/results/<phase>/<name>/.
#
#   1. BOOTS fresh reboots, boot timing collected after each (collect.sh boot)
#   2. after the last boot: idle 5 min, then idle RAM (collect.sh ram)
#   3. size / package inventory (collect.sh static)
#   4. GPU benchmark series with NVML telemetry and peak RAM (collect.sh bench)
#
# Usage: measure/run-target.sh --host IP --mac MAC --name NAME [--phase phase1]
#          [--boots 5] [--bench-runs 7] [--bench-cmd CMD] [--marker FILE] [--idle 300]
# The target's IP can change across reboots (phone hotspot DHCP), so it is
# re-found by MAC address on the /24 after every reboot.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HOST= MAC= NAME= PHASE=phase1 BOOTS=5 RUNS=7 BENCH_CMD= MARKER= IDLE=300
while (($#)); do case $1 in
  --host) HOST=$2; shift 2;; --mac) MAC=${2,,}; shift 2;; --name) NAME=$2; shift 2;;
  --phase) PHASE=$2; shift 2;; --boots) BOOTS=$2; shift 2;; --bench-runs) RUNS=$2; shift 2;;
  --bench-cmd) BENCH_CMD=$2; shift 2;; --marker) MARKER=$2; shift 2;; --idle) IDLE=$2; shift 2;;
  *) echo "unknown arg $1" >&2; exit 1;; esac; done
[[ -n $HOST && -n $MAC && -n $NAME ]] || { sed -n 2,15p "$0"; exit 1; }
OUT="$REPO/docs/results/$PHASE/$NAME"; mkdir -p "$OUT/raw"
KH="$REPO/cache/known_hosts_trackc"
SSH=(ssh -i "$HOME/.ssh/trackc_ed25519" -o BatchMode=yes -o ConnectTimeout=5
     -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=error)  # lab LAN; baseline and custom share the IP but not the host key
log() { echo "[$(date +%T)] $*" | tee -a "$OUT/run.log"; }
t() { "${SSH[@]}" "trackc@$HOST" "$@"; }

find_host() {  # wait (max ~6 min) for the target to answer SSH; re-find by MAC if the IP moved
  local net=${HOST%.*} i
  for _ in $(seq 70); do
    t true 2>/dev/null && return 0
    for i in $(seq 1 254); do (ping -c1 -W1 "$net.$i" >/dev/null 2>&1 &); done; sleep 2
    i=$(ip neigh | awk -v m="$MAC" 'tolower($5)==m && $1 ~ /^[0-9.]+$/ {print $1; exit}')
    [[ -n $i && $i != "$HOST" ]] && { HOST=$i; log "target moved to $HOST"; }
    sleep 3
  done
  log "target not reachable"; return 1
}

push_collector() {
  scp -q -i "$HOME/.ssh/trackc_ed25519" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=error \
    "$REPO/measure/collect.sh" "trackc@$HOST:/tmp/trackc-collect.sh"
  scp -q -i "$HOME/.ssh/trackc_ed25519" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=error \
    "$REPO/measure/bench-appliance.sh" "trackc@$HOST:/tmp/trackc-bench-appliance.sh"
}
collect() { push_collector; t "sudo BENCH_CMD='$BENCH_CMD' BENCH_RUNS=$RUNS BENCH_START_MARKER='$MARKER' bash /tmp/trackc-collect.sh /var/lib/trackc/measure $*"; }

log "== $NAME: $BOOTS boots, $RUNS bench runs, host $HOST"
find_host
t 'cat /sys/class/power_supply/AC*/online /sys/class/power_supply/ACAD/online 2>/dev/null | head -1' \
  | grep -q 1 || log "WARNING: target not on AC power"
t 'sudo rm -rf /var/lib/trackc/measure'

# Baseline: build the benchmark with the host's nvcc if it is not there yet.
if [[ -z $BENCH_CMD ]]; then
  BENCH_CMD=/opt/trackc/trackc_bench
  if ! t "test -x $BENCH_CMD"; then
    log "building trackc_bench on target"
    scp -q -i "$HOME/.ssh/trackc_ed25519" -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=error \
      "$REPO/benchmark/src/trackc_bench.cu" "trackc@$HOST:/tmp/"
    t 'cd /tmp && /usr/local/cuda/bin/nvcc -O2 -arch=sm_89 -o trackc_bench trackc_bench.cu -lcublas && sudo install -m 755 trackc_bench /opt/trackc/'
  fi
fi

for b in $(seq "$BOOTS"); do
  log "boot $b/$BOOTS: rebooting"
  t 'sudo systemctl reboot' 2>/dev/null || true
  sleep 25
  find_host
  collect boot
  log "boot $b: $(t 'systemd-analyze | head -1')"
done

up=$(t 'cut -d. -f1 /proc/uptime')
if (( up < IDLE )); then log "idling $((IDLE - up)) s before RAM measurement"; sleep $((IDLE - up)); fi
collect ram;    log "ram idle done"
collect static; log "static done"
log "benchmark: $RUNS runs"
collect bench;  log "bench done"

t 'sudo tar -C /var/lib/trackc/measure -cf - .' | tar -C "$OUT/raw" -xf -
log "raw results in $OUT/raw"
python3 "$REPO/measure/summarize.py" "$OUT" | tee "$OUT/summary.md"
