#!/usr/bin/env bash
# install-remote-access.sh: LAB-ONLY remote access so Claude Code on Laptop 1
# can drive the baseline running on Laptop 2 (over a phone hotspot).
# Deviations from stock, all documented for the report:
#   - openssh-server, key-only, no root login, no passwords
#   - Wi-Fi (netplan + wpasupplicant + linux-firmware), mDNS name baseline.local
#   - passwordless sudo for the lab user (non-interactive measurement scripts)
# Must be removed/accounted for when measuring package count and size.
# Usage (in-target or on the baseline): sudo ./install-remote-access.sh <stage-dir>
set -euo pipefail
SRC="${1:-/root/trackc}"
USER_NAME=trackc
export DEBIAN_FRONTEND=noninteractive
apt-get -y -o DPkg::Options::=--force-unsafe-io install \
  openssh-server wpasupplicant linux-firmware wireless-regdb iw avahi-daemon

install -d -m 0700 -o "$USER_NAME" -g "$USER_NAME" "/home/$USER_NAME/.ssh"
install -m 0600 -o "$USER_NAME" -g "$USER_NAME" "$SRC/authorized_keys" "/home/$USER_NAME/.ssh/authorized_keys"
cat > /etc/ssh/sshd_config.d/10-trackc.conf <<'CONF'
# Lab access only: key auth, no root, no passwords.
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AllowUsers trackc
CONF
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/90-trackc-lab
chmod 0440 /etc/sudoers.d/90-trackc-lab

if [[ -f $SRC/60-trackc-wifi.yaml ]]; then
  install -m 0600 "$SRC/60-trackc-wifi.yaml" /etc/netplan/60-trackc-wifi.yaml
fi
systemctl enable ssh avahi-daemon
echo "install-remote-access: done"
