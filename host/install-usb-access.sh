#!/usr/bin/env bash
# install-usb-access.sh: ONE-TIME host change (needs sudo).
# Gives the logged-in user read/write access to exactly the two project USB
# sticks (matched by USB serial), so build/install scripts can write them
# without sudo. No other disk is affected. Undo: sudo rm the rule file.
#
# Usage: sudo host/install-usb-access.sh
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
USER_NAME="${SUDO_USER:?run via sudo from your user account}"
RULE=/etc/udev/rules.d/99-trackc-usb.rules
cat > "$RULE" <<RULES
# Track C project USB sticks only (installed by host/install-usb-access.sh)
# 64 GB SanDisk Cruzer Blade (dev/measurement drive)
SUBSYSTEM=="block", ENV{ID_SERIAL_SHORT}=="03018820042024224003", OWNER="$USER_NAME", MODE="0660"
# 8 GB Flash Disk (installer / release-candidate drive)
SUBSYSTEM=="block", ENV{ID_SERIAL_SHORT}=="CCYYMMDDHHmmSSBLOUZ7", OWNER="$USER_NAME", MODE="0660"
RULES
udevadm control --reload
udevadm trigger --subsystem-match=block --action=change
sleep 1
ls -l /dev/disk/by-id/ | grep -E "Cruzer_Blade|Flash_Disk" || true
echo "Installed $RULE for user $USER_NAME"
