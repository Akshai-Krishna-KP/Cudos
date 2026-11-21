#!/usr/bin/env bash
# customize.sh: mmdebstrap customize hook for build-rootfs.sh. $1 = rootfs, $2 = variant.
#   1. NVIDIA: build the open kernel modules for the image kernel with DKMS, keep the
#      .ko files and the nvidia-smi binary, then purge compilers/headers/DKMS.
#   2. Overlay files, users, preloaded benchmark image, services, hardening.
#   3. DEV variant: lab remote access.
#   4. initramfs, cleanup.
set -euo pipefail
R=$1; VARIANT=$2; KERNEL=${3:-debian}; SRC=/src
source "$SRC/build/versions.env"
ch() { chroot "$R" "$@"; }
if [[ $KERNEL == trackc* ]]; then
  # Our Phase 3 kernel: image + headers (headers only for the DKMS build, purged below).
  KDIR=$SRC/out/kernel; [[ $KERNEL == trackc-iso ]] && KDIR=$SRC/out/kernel-iso
  cp "$KDIR"/linux-image-*-trackc_*.deb "$KDIR"/linux-headers-*-trackc_*.deb "$R/tmp/"
  DEBIAN_FRONTEND=noninteractive ch sh -c 'dpkg -i /tmp/linux-headers-*.deb /tmp/linux-image-*.deb' >/dev/null
  rm -f "$R"/tmp/linux-*.deb
fi
KVER=$(ls "$R/lib/modules" | sort -V | tail -1)
NVV=${NVIDIA_DEB_VERSION%-*}
echo "customize: kernel $KVER, nvidia $NVV, variant $VARIANT"

# --- 1. NVIDIA open kernel modules (built here, unsigned: Secure Boot off, documented)
ch dkms status
# Reproducible module: NVIDIA stamps user@host and `date` into nvidia.ko/nvidia-modeset.ko
# (utils.mk: NV_BUILD_USER/NV_BUILD_HOST/DATE ?=). Pin them; --force rebuilds the copy
# the package postinst may already have built without these settings.
ch env NV_BUILD_USER=trackc NV_BUILD_HOST=trackc-builder DATE="date -u -d @$SOURCE_DATE_EPOCH" \
  dkms build --force "nvidia/$NVV" -k "$KVER" || { cat "$R/var/lib/dkms/nvidia/$NVV/build/make.log" | tail -40; exit 1; }
ch dkms install --force "nvidia/$NVV" -k "$KVER"
mkdir -p "$R/root/keep/ko"
find "$R/lib/modules/$KVER/updates" -name 'nvidia*.ko*' -exec cp {} "$R/root/keep/ko/" \;
ls -l "$R/root/keep/ko"
cp "$R/usr/bin/nvidia-smi" "$R/root/keep/nvidia-smi"
# firmware-nvidia-gsp must stay although only the dkms package depends on it.
ch apt-mark manual firmware-nvidia-gsp >/dev/null
ch apt-mark auto nvidia-kernel-open-dkms nvidia-driver-cuda dkms libelf1t64 >/dev/null 2>&1 || true
ch apt-mark auto linux-headers-amd64 >/dev/null 2>&1 || true
# Purge everything that was only needed to compile the modules. RecommendsImportant=false:
# otherwise apt keeps the compiler because some installed package merely recommends it.
NOREC=(-o APT::AutoRemove::RecommendsImportant=false -o APT::AutoRemove::SuggestsImportant=false)
BUILD_ONLY=$(ch dpkg-query -W -f '${Package}\n' | grep -E \
  '^(gcc|g\+\+|cpp)(-[0-9]+)?(-x86-64-linux-gnu)?$|^linux-(headers|kbuild)-|^make$|^binutils|^lib(asan|tsan|ubsan|hwasan|lsan)[0-9]+$|^(libc6-dev|libc-dev-bin|linux-libc-dev|libcrypt-dev|patch)$|^lib(gcc|stdc\+\+)-[0-9]+-dev$' || true)
echo "purging build-only packages:" $BUILD_ONLY
DEBIAN_FRONTEND=noninteractive ch apt-get purge -y -q "${NOREC[@]}" --autoremove \
  nvidia-kernel-open-dkms nvidia-driver-cuda linux-headers-amd64 dkms $BUILD_ONLY >/dev/null
# gcc-14-base is a runtime dependency of libgcc-s1/libstdc++6 and may stay.
mkdir -p "$R/lib/modules/$KVER/updates/nvidia"
mv "$R"/root/keep/ko/* "$R/lib/modules/$KVER/updates/nvidia/"
# nvidia-smi only needs libnvidia-ml.so.1 (kept); extracted binary is a non-dpkg component.
install -m 755 "$R/root/keep/nvidia-smi" "$R/usr/bin/nvidia-smi"
rm -rf "$R/root/keep" "$R/var/lib/dkms" "$R/usr/src/"nvidia-*
ch depmod "$KVER"
ch sh -c 'dpkg -l | grep -E "^ii +(gcc|g\+\+|make|dkms|linux-headers|cpp)" | grep -v "gcc-14-base" && exit 1 || true'

# --- 2. appliance
cp -a "$SRC/overlay/rootfs/." "$R/"
# Unprivileged benchmark user; home on /var (persist, exec allowed for container storage).
ch useradd --system --create-home --home-dir /var/lib/trackc-bench --shell /usr/sbin/nologin bench
echo "bench:100000:65536" > "$R/etc/subuid"; echo "bench:100000:65536" > "$R/etc/subgid"
mkdir -p "$R/usr/share/trackc"
install -m 644 "$SRC/out/trackc-bench.tar" "$R/usr/share/trackc/trackc-bench.tar"
ch systemctl enable gpu-autoconfig.service trackc-bench.service trackc-issue.service nftables.service nvidia-powerd.service >/dev/null
ch systemctl enable trackc-selftest.service >/dev/null   # boot-time check of read-only root + mount flags
ch systemctl mask systemd-timesyncd.service apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
mkdir -p "$R/var/log/journal"
# No apt metadata or NVIDIA repo config in the image (read-only appliance, no updates in place).
rm -f "$R/etc/apt/sources.list.d/"*.list
rm -rf "$R/var/lib/apt/lists/"*

# --- 3. dev variant: lab remote access (not part of the graded release image)
if [[ $VARIANT == dev ]]; then
  cp -a "$SRC/overlay/rootfs-dev/." "$R/"
  # The appliance user is "lazarus" (password "lazarus", chosen by the team for the demo).
  # The password only works on the local console: SSH stays key-only (sshd AllowUsers lazarus).
  LU=lazarus
  ch useradd --create-home --shell /bin/bash --groups sudo "$LU"
  echo "$LU:lazarus" | ch chpasswd
  install -d -m 700 "$R/home/$LU/.ssh"
  install -m 600 "$SRC/out/dev-secrets/authorized_keys" "$R/home/$LU/.ssh/authorized_keys"
  ch chown -R "$LU:$LU" "/home/$LU"
  # cuda-dev: own subordinate ID range (useradd may have reused bench's), workspace link
  # (~/cuda -> /var/lib/cuda-work/$LU, created at boot by tmpfiles), example sources.
  sed -i "/^$LU:/d" "$R/etc/subuid" "$R/etc/subgid"
  echo "$LU:200000:65536" >> "$R/etc/subuid"; echo "$LU:200000:65536" >> "$R/etc/subgid"
  ln -sfn "/var/lib/cuda-work/$LU" "$R/home/$LU/cuda"; ch chown -h "$LU:$LU" "/home/$LU/cuda"
  # cuda-dev install / lazarus-install: library list + NVIDIA ubuntu2404 repo key (pinned)
  install -m 644 "$SRC/cache/nvidia-ubuntu2404/cuda-archive-keyring.gpg" "$R/usr/share/trackc/cuda-dev/cuda-archive-keyring.gpg"
  install -d "$R/usr/share/trackc/examples"
  install -m 644 "$SRC"/benchmark/examples/* "$SRC/benchmark/src/trackc_bench.cu" "$R/usr/share/trackc/examples/"
  # DNS for Wi-Fi/DHCP (resolv.conf points at the systemd-resolved stub).
  ch systemctl enable systemd-resolved.service >/dev/null
  # shellcheck source=/dev/null
  source "$SRC/cache/wifi.env"
  args=("$WIFI_SSID" "$WIFI_PASSWORD"); [[ -n ${WIFI2_SSID:-} ]] && args+=("$WIFI2_SSID" "$WIFI2_PASSWORD")
  install -d "$R/etc/wpa_supplicant"
  python3 "$SRC/baseline/render-wifi-conf.py" "${args[@]}" > "$R/etc/wpa_supplicant/trackc-wifi.conf"
  chmod 600 "$R/etc/wpa_supplicant/trackc-wifi.conf"
  ch systemctl enable systemd-networkd.service trackc-wifi-start.service ssh.service >/dev/null
  echo trackc-dev > "$R/etc/hostname"; sed -i 's/\ttrackc$/\ttrackc-dev/' "$R/etc/hosts"
fi

# --- 3b. portable variant: shareable image, no lab secrets (see overlay/rootfs-portable)
if [[ $VARIANT == portable ]]; then
  # Reuse the dev pieces that hold no secrets: cuda-dev, Wi-Fi units (used only if the
  # owner provides trackc/wifi.txt on the stick), examples.
  install -m 755 "$SRC/overlay/rootfs-dev/usr/local/bin/cuda-dev" "$SRC/overlay/rootfs-dev/usr/local/bin/lazarus-install" "$R/usr/local/bin/"
  install -d "$R/usr/share/trackc/cuda-dev"
  install -m 644 "$SRC/overlay/rootfs-dev/usr/share/trackc/cuda-dev/libraries.txt" "$R/usr/share/trackc/cuda-dev/"
  install -m 644 "$SRC/cache/nvidia-ubuntu2404/cuda-archive-keyring.gpg" "$R/usr/share/trackc/cuda-dev/"
  install -m 755 "$SRC/overlay/rootfs-dev/usr/local/sbin/trackc-wifi-start" "$R/usr/local/sbin/"
  install -m 644 "$SRC"/overlay/rootfs-dev/etc/systemd/system/trackc-wifi*.service "$R/etc/systemd/system/"
  install -m 644 "$SRC/overlay/rootfs-dev/etc/systemd/network/25-trackc-wifi.network" "$R/etc/systemd/network/"
  cp -a "$SRC/overlay/rootfs-portable/." "$R/"
  ch useradd --create-home --shell /bin/bash lazarus
  echo "lazarus:lazarus" | ch chpasswd           # console auto-login anyway; SSH stays key-only
  sed -i '/^lazarus:/d' "$R/etc/subuid" "$R/etc/subgid"
  echo "lazarus:200000:65536" >> "$R/etc/subuid"; echo "lazarus:200000:65536" >> "$R/etc/subgid"
  ln -sfn /var/lib/cuda-work/lazarus "$R/home/lazarus/cuda"; ch chown -h lazarus:lazarus /home/lazarus/cuda
  install -d "$R/usr/share/trackc/examples"
  install -m 644 "$SRC"/benchmark/examples/* "$SRC/benchmark/src/trackc_bench.cu" "$R/usr/share/trackc/examples/"
  rm -f "$R"/etc/ssh/ssh_host_*                      # no shared host keys in a shared image
  ch systemctl disable ssh.service ssh.socket >/dev/null 2>&1 || true
  ch systemctl enable systemd-networkd.service systemd-resolved.service trackc-grow-persist.service trackc-provision.service >/dev/null
  ch passwd -l root >/dev/null
fi

# --- 3c. live ISO kernel: initramfs finds the ISO and loop-mounts live/rootfs.squashfs
if [[ $KERNEL == trackc-iso ]]; then
  cp -a "$SRC/overlay/iso/etc/initramfs-tools/scripts" "$R/etc/initramfs-tools/"
  grep -v '^#' "$SRC/overlay/iso/etc/initramfs-tools/modules-iso" >> "$R/etc/initramfs-tools/modules"
fi

# --- 4. initramfs + cleanup
ch update-initramfs -u -k "$KVER"
rm -f "$R/etc/machine-id" && touch "$R/etc/machine-id"
rm -rf "$R/var/log/"*.log "$R/var/cache/debconf/"*-old "$R/var/lib/dpkg/"*-old "$R/var/cache/apt/"*.bin
echo "customize: done"
