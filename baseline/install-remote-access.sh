#!/usr/bin/env bash
# install-remote-access.sh: LAB-ONLY remote access so Claude Code on Laptop 1
# can drive the baseline running on Laptop 2 (over a phone hotspot).
# Deviations from stock, all documented for the report:
#   - openssh-server, key-only, no root login, no passwords
#   - Wi-Fi (wpasupplicant + networkd + linux-firmware), mDNS name baseline.local
#   - internal (non-USB) disks forced read-only by udev, so nothing run on the
#     baseline can ever write to the host laptop's own drives
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

# Wi-Fi for any card name: udev starts trackc-wifi@<iface> for each wlan device
# (after naming, hence $name in a 99- rule); networkd does DHCP on Type=wlan.
if [[ -f $SRC/trackc-wifi.conf ]]; then
  install -m 0600 "$SRC/trackc-wifi.conf" /etc/wpa_supplicant/trackc-wifi.conf
fi
cat > /etc/systemd/system/trackc-wifi@.service <<'UNIT'
[Unit]
Description=Lab hotspot Wi-Fi on %I (Track C remote access)
BindsTo=sys-subsystem-net-devices-%i.device
After=sys-subsystem-net-devices-%i.device
Before=network.target
Wants=network.target
ConditionPathExists=/etc/wpa_supplicant/trackc-wifi.conf

[Service]
ExecStart=/usr/sbin/wpa_supplicant -i %I -D nl80211 -c /etc/wpa_supplicant/trackc-wifi.conf
Restart=on-failure
RestartSec=5
UNIT
# Boot-time starter: waits (max 30 s) for Wi-Fi interfaces, starts trackc-wifi@<iface>.
# (A udev SYSTEMD_WANTS rule was tried first; it did not fire on Laptop 2.)
cat > /usr/local/sbin/trackc-wifi-start <<'SH'
#!/bin/sh
for _ in $(seq 30); do
  found=
  for i in /sys/class/net/*; do
    grep -q '^DEVTYPE=wlan$' "$i/uevent" 2>/dev/null || continue
    found=1; systemctl start --no-block "trackc-wifi@$(basename "$i").service"
  done
  [ -n "$found" ] && exit 0; sleep 1
done
echo "no Wi-Fi interface found"
SH
chmod 0755 /usr/local/sbin/trackc-wifi-start
cat > /etc/systemd/system/trackc-wifi-start.service <<'UNIT'
[Unit]
Description=Start lab hotspot Wi-Fi on every wlan interface (Track C remote access)
After=systemd-udevd.service systemd-networkd.service
Before=network-online.target
ConditionPathExists=/etc/wpa_supplicant/trackc-wifi.conf

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/trackc-wifi-start

[Install]
WantedBy=multi-user.target
UNIT
rm -f /etc/udev/rules.d/99-trackc-wifi.rules
cat > /etc/systemd/network/25-trackc-wifi.network <<'NET'
[Match]
Type=wlan

[Network]
DHCP=ipv4

[Link]
# Do not hold boot (systemd-networkd-wait-online) on the lab Wi-Fi.
RequiredForOnline=no
NET
rm -f /etc/netplan/60-trackc-wifi.yaml   # older installs used netplan for Wi-Fi

# Never write to the laptop's internal drives (NVMe / SATA / eMMC). USB is untouched.
cat > /etc/udev/rules.d/61-trackc-internal-disks-ro.rules <<'RULE'
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="nvme*|mmcblk*", RUN+="/usr/sbin/blockdev --setro $devnode"
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd*", ENV{ID_BUS}=="ata", RUN+="/usr/sbin/blockdev --setro $devnode"
RULE
systemctl enable ssh avahi-daemon trackc-wifi-start.service
apt-get clean
echo "install-remote-access: done"
