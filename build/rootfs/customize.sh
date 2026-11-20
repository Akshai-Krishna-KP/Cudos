#!/usr/bin/env bash
# customize.sh: mmdebstrap customize hook for build-rootfs.sh. $1 = rootfs, $2 = variant.
#   1. NVIDIA: build the open kernel modules for the image kernel with DKMS, keep the
#      .ko files and the nvidia-smi binary, then purge compilers/headers/DKMS.
#   2. Overlay files, users, preloaded benchmark image, services, hardening.
#   3. DEV variant: lab remote access.
#   4. initramfs, cleanup.
set -euo pipefail
R=$1; VARIANT=$2; SRC=/src
source "$SRC/build/versions.env"
ch() { chroot "$R" "$@"; }
KVER=$(ls "$R/lib/modules" | sort -V | tail -1)
NVV=${NVIDIA_DEB_VERSION%-*}
echo "customize: kernel $KVER, nvidia $NVV, variant $VARIANT"

# --- 1. NVIDIA open kernel modules (built here, unsigned: Secure Boot off, documented)
ch dkms status
ch dkms build "nvidia/$NVV" -k "$KVER" || { cat "$R/var/lib/dkms/nvidia/$NVV/build/make.log" | tail -40; exit 1; }
ch dkms install --force "nvidia/$NVV" -k "$KVER"
mkdir -p "$R/root/keep/ko"
find "$R/lib/modules/$KVER/updates" -name 'nvidia*.ko*' -exec cp {} "$R/root/keep/ko/" \;
ls -l "$R/root/keep/ko"
cp "$R/usr/bin/nvidia-smi" "$R/root/keep/nvidia-smi"
# firmware-nvidia-gsp must stay although only the dkms package depends on it.
ch apt-mark manual firmware-nvidia-gsp >/dev/null
ch apt-mark auto nvidia-kernel-open-dkms nvidia-driver-cuda linux-headers-amd64 dkms >/dev/null
DEBIAN_FRONTEND=noninteractive ch apt-get purge -y -q --autoremove nvidia-kernel-open-dkms nvidia-driver-cuda linux-headers-amd64 dkms >/dev/null
mkdir -p "$R/lib/modules/$KVER/updates/nvidia"
mv "$R"/root/keep/ko/* "$R/lib/modules/$KVER/updates/nvidia/"
# nvidia-smi only needs libnvidia-ml.so.1 (kept); extracted binary is a non-dpkg component.
install -m 755 "$R/root/keep/nvidia-smi" "$R/usr/bin/nvidia-smi"
rm -rf "$R/root/keep" "$R/var/lib/dkms" "$R/usr/src/"nvidia-*
ch depmod "$KVER"
ch sh -c 'dpkg -l | grep -E "^ii +(gcc|g\+\+|make|dkms|linux-headers|cpp)" && exit 1 || true'

# --- 2. appliance
cp -a "$SRC/overlay/rootfs/." "$R/"
# Unprivileged benchmark user; home on /var (persist, exec allowed for container storage).
ch useradd --system --create-home --home-dir /var/lib/trackc-bench --shell /usr/sbin/nologin bench
echo "bench:100000:65536" > "$R/etc/subuid"; echo "bench:100000:65536" > "$R/etc/subgid"
mkdir -p "$R/usr/share/trackc"
install -m 644 "$SRC/out/trackc-bench.tar" "$R/usr/share/trackc/trackc-bench.tar"
ch systemctl enable gpu-autoconfig.service trackc-bench.service trackc-dashboard.service nftables.service >/dev/null
ch systemctl disable trackc-selftest.service >/dev/null 2>&1 || true
ch systemctl mask getty@tty1.service systemd-timesyncd.service apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
mkdir -p "$R/var/log/journal"
# No apt metadata or NVIDIA repo config in the image (read-only appliance, no updates in place).
rm -f "$R/etc/apt/sources.list.d/"*.list
rm -rf "$R/var/lib/apt/lists/"*

# --- 3. dev variant: lab remote access (not part of the graded release image)
if [[ $VARIANT == dev ]]; then
  cp -a "$SRC/overlay/rootfs-dev/." "$R/"
  ch useradd --create-home --shell /bin/bash --groups sudo trackc
  install -d -m 700 "$R/home/trackc/.ssh"
  install -m 600 "$SRC/out/dev-secrets/authorized_keys" "$R/home/trackc/.ssh/authorized_keys"
  ch chown -R trackc:trackc /home/trackc
  # Console fallback login (same generated password as the baseline, from cache/).
  if [[ -f $SRC/cache/baseline-credentials.txt ]]; then
    pw=$(sed -n 's/^password=//p' "$SRC/cache/baseline-credentials.txt")
    echo "trackc:$pw" | ch chpasswd
  fi
  # shellcheck source=/dev/null
  source "$SRC/cache/wifi.env"
  args=("$WIFI_SSID" "$WIFI_PASSWORD"); [[ -n ${WIFI2_SSID:-} ]] && args+=("$WIFI2_SSID" "$WIFI2_PASSWORD")
  install -d "$R/etc/wpa_supplicant"
  python3 "$SRC/baseline/render-wifi-conf.py" "${args[@]}" > "$R/etc/wpa_supplicant/trackc-wifi.conf"
  chmod 600 "$R/etc/wpa_supplicant/trackc-wifi.conf"
  ch systemctl enable systemd-networkd.service trackc-wifi-start.service ssh.service >/dev/null
  echo trackc-dev > "$R/etc/hostname"; sed -i 's/\ttrackc$/\ttrackc-dev/' "$R/etc/hosts"
fi

# --- 4. initramfs + cleanup
ch update-initramfs -u -k "$KVER"
rm -f "$R/etc/machine-id" && touch "$R/etc/machine-id"
rm -rf "$R/var/log/"*.log "$R/var/cache/debconf/"*-old "$R/var/lib/dpkg/"*-old "$R/var/cache/apt/"*.bin
echo "customize: done"
