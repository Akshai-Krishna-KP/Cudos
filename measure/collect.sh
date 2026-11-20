#!/usr/bin/env bash
# collect.sh: runs ON THE TARGET (baseline or custom image) as root and writes raw
# measurement output into a directory. Driven from Laptop 1 by measure/run-target.sh.
#
# Usage: collect.sh <outdir> <mode>
#   mode=boot    boot timing of the current boot        -> boot-<boot_id>.txt
#   mode=static  size / package / component inventory   -> static.txt
#   mode=ram     idle RAM (free + PSS from smaps_rollup) -> ram-idle.txt
#   mode=bench   GPU benchmark runs + NVML telemetry      -> bench.jsonl, bench-telemetry.csv, ram-load.txt
# Env (bench): BENCH_CMD (default /opt/trackc/trackc_bench), BENCH_RUNS (default 7)
# Env (boot):  BENCH_START_MARKER  file whose mtime is when the benchmark started (custom image)
set -euo pipefail
OUT=${1:?outdir}; MODE=${2:?mode}
mkdir -p "$OUT"
run() { echo "\$ $*"; "$@" 2>&1 || echo "[exit $?]"; echo; }

# PSS total over all processes (kB), from /proc/*/smaps_rollup (no smem needed on target).
pss_total() { cat /proc/[0-9]*/smaps_rollup 2>/dev/null | awk '/^Pss:/{s+=$2} END{print s}'; }

case $MODE in
boot)
  bid=$(cat /proc/sys/kernel/random/boot_id)
  # Wait until systemd reports the boot as finished.
  for _ in $(seq 120); do systemd-analyze >/dev/null 2>&1 && break; sleep 2; done
  {
    echo "# boot $(date -Is) boot_id=$bid"
    run systemd-analyze
    run systemd-analyze critical-chain --no-pager
    run sh -c 'systemd-analyze blame --no-pager | head -25'
    echo "\$ kernel timestamp of first userspace (dmesg 'Run /init' / 'systemd')"
    dmesg | grep -m3 -E 'Run /init|systemd\[1\]: systemd [0-9]' || true; echo
    if [[ -n ${BENCH_START_MARKER:-} && -e $BENCH_START_MARKER ]]; then
      # seconds from kernel start to benchmark start = (marker mtime - boot time)
      btime=$(awk '/^btime/{print $2}' /proc/stat)
      echo "time_to_benchmark_s=$(( $(stat -c %Y "$BENCH_START_MARKER") - btime ))"
    else
      echo "time_to_benchmark_s=n/a"
    fi
  } > "$OUT/boot-$bid.txt"
  ;;
static)
  {
    echo "# static $(date -Is)"
    run cat /etc/os-release
    run uname -a
    echo "packages_dpkg=$(dpkg -l 2>/dev/null | grep -cE '^(ii|hi)' || echo 0)"
    echo "rootfs_used_bytes=$(du -sxb / 2>/dev/null | cut -f1)"
    echo
    run df -B1 -x tmpfs -x devtmpfs -x squashfs -x overlay
    run df -B1 -t squashfs -t overlay
    run findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
    run du -sxb /boot /usr /var /opt /lib/modules /lib/firmware /usr/local 2>/dev/null
    echo "\$ installed size by group (dpkg Installed-Size, KiB)"
    dpkg-query -W -f '${Installed-Size}\t${Package}\n' 2>/dev/null | awk -F'\t' '
      { g="other" }
      $2 ~ /^(cuda-|libcublas|libcufft|libcurand|libcusolver|libcusparse|libnpp|libnvjitlink|libnvjpeg|libnvfatbin|libcufile|nsight|libnvptxcompiler|libnvvm|gds-tools)/ { g="cuda-toolkit+libs" }
      $2 ~ /^(cudnn|libcudnn)/ { g="cudnn" }
      $2 ~ /^(nvidia-|libnvidia-|xserver-xorg-video-nvidia|libxnvctrl)/ { g="nvidia-driver+ctk" }
      $2 ~ /^(linux-firmware|linux-modules|linux-image|linux-headers)/ { g="kernel+firmware" }
      $2 ~ /^(openssh-server|wpasupplicant|wireless-regdb|iw|avahi-daemon)$/ { g="lab-remote-access" }
      $2 ~ /^(podman|conmon|crun|runc|containernetworking|golang-github-containers|buildah|catatonit|netavark|aardvark-dns|slirp4netns|fuse-overlayfs|uidmap)/ { g="containers" }
      { s[g]+=$1 } END { for (k in s) printf "%-20s %10d KiB\n", k, s[k] }' | sort
    echo
    echo "\$ top 25 packages by installed size (KiB)"
    dpkg-query -W -f '${Installed-Size}\t${Package}\n' 2>/dev/null | sort -rn | sed -n '1,25p'
    echo
    echo "\$ lab-only remote-access packages (excluded from 'identical functionality')"
    dpkg-query -W -f '${Installed-Size}\t${Package}\n' openssh-server wpasupplicant wireless-regdb iw avahi-daemon 2>/dev/null || true
    echo
    run sh -c 'ls /var/lib/containers/storage 2>/dev/null && podman images 2>/dev/null'
  } > "$OUT/static.txt"
  ;;
ram)
  {
    echo "# ram-idle $(date -Is) uptime_s=$(cut -d' ' -f1 /proc/uptime)"
    run free -m
    echo "pss_total_kib=$(pss_total)"
    echo
    echo "\$ top 15 processes by PSS (KiB)"
    for f in /proc/[0-9]*/smaps_rollup; do
      p=${f%/smaps_rollup}; pss=$(awk '/^Pss:/{print $2}' "$f" 2>/dev/null) || continue
      [[ -n $pss ]] && printf '%8d %s\n' "$pss" "$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null | cut -c1-80)"
    done | sort -rn | sed -n '1,15p'
    echo
    run sh -c 'systemctl list-units --type=service --state=running --no-legend --no-pager | wc -l'
    run sh -c 'ps -e --no-headers | wc -l'
  } > "$OUT/ram-idle.txt"
  ;;
bench)
  CMD=${BENCH_CMD:-/opt/trackc/trackc_bench}; RUNS=${BENCH_RUNS:-7}
  # Custom image: pause the auto-start benchmark loop so it does not overlap the measured runs.
  svc=0; systemctl is-active -q trackc-bench.service 2>/dev/null && { systemctl stop trackc-bench.service; svc=1; }
  # NVML telemetry every 200 ms for the whole series (temperature, power, clocks, throttling).
  nvidia-smi --query-gpu=timestamp,temperature.gpu,power.draw,clocks.sm,clocks.mem,pstate,clocks_event_reasons.active \
    --format=csv -lms 200 > "$OUT/bench-telemetry.csv" 2>&1 &
  smi=$!
  # Peak RAM under load: sample used memory every 200 ms.
  ( peak=0; while :; do u=$(free -m | awk '/^Mem:/{print $3}'); (( u > peak )) && peak=$u && echo "$peak" > "$OUT/.ram-peak"; sleep 0.2; done ) &
  sampler=$!
  : > "$OUT/bench.jsonl"
  for i in $(seq "$RUNS"); do
    t=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits)
    $CMD --label "run$i" | sed "s/}\$/,\"temp_start_c\":$t}/" >> "$OUT/bench.jsonl"
    sleep 5   # let the GPU cool a little between runs
  done
  kill $smi $sampler 2>/dev/null || true; wait 2>/dev/null || true
  { echo "# ram-load $(date -Is)"; echo "used_mib_peak=$(cat "$OUT/.ram-peak")"; } > "$OUT/ram-load.txt"
  rm -f "$OUT/.ram-peak"
  (( svc )) && systemctl start trackc-bench.service
  ;;
*) echo "unknown mode $MODE" >&2; exit 1 ;;
esac
echo "collect.sh $MODE: ok"
