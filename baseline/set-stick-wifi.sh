#!/usr/bin/env bash
# set-stick-wifi.sh: rewrite the lab hotspot config (/etc/netplan/60-trackc-wifi.yaml)
# on the installed baseline stick, without mounting it or using sudo
# (debugfs -w on the unmounted root partition; needs host/install-usb-access.sh).
# Use when the phone hotspot changes. Reads cache/wifi.env (WIFI_*, optional WIFI2_*).
# Usage: baseline/set-stick-wifi.sh 03018820042024224003
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SERIAL_EXPECTED="03018820042024224003"   # 64 GB SanDisk Cruzer Blade
[[ ${1:-} == "$SERIAL_EXPECTED" ]] || { echo "usage: $0 $SERIAL_EXPECTED" >&2; exit 1; }
PART=$(readlink -f "/dev/disk/by-id/usb-SanDisk_Cruzer_Blade_${SERIAL_EXPECTED}-0:0-part2")
[[ -b $PART && $(lsblk -no TRAN "$(lsblk -no PKNAME "$PART" | sed 's|^|/dev/|')") == usb ]] \
  || { echo "baseline root partition not found on USB" >&2; exit 1; }
[[ $(lsblk -no LABEL "$PART") == baseline-root ]] || { echo "$PART is not baseline-root" >&2; exit 1; }
if lsblk -no MOUNTPOINT "$PART" | grep -q .; then echo "$PART is mounted; unmount first" >&2; exit 1; fi

# shellcheck source=/dev/null
source "$REPO/cache/wifi.env"
args=("${WIFI_SSID:?}" "${WIFI_PASSWORD:?}")
[[ -n ${WIFI2_SSID:-} ]] && args+=("$WIFI2_SSID" "${WIFI2_PASSWORD:?}")
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
python3 "$REPO/baseline/render-wifi-netplan.py" "${args[@]}" > "$tmp"

F=/etc/netplan/60-trackc-wifi.yaml
debugfs -w -f - "$PART" >/dev/null 2>&1 <<CMDS
rm $F
write $tmp $F
set_inode_field $F uid 0
set_inode_field $F gid 0
set_inode_field $F mode 0100600
CMDS
# Verify: owner/mode and that every SSID is present (passwords are not printed).
debugfs -R "stat $F" "$PART" 2>/dev/null | grep -E '^(Inode|User):'
debugfs -R "cat $F" "$PART" 2>/dev/null | grep -F -c '{password:' | xargs echo "access points on stick:"
e2fsck -fn "$PART" >/dev/null && echo "filesystem clean"
