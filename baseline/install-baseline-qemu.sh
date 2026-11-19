#!/usr/bin/env bash
# install-baseline-qemu.sh: unattended install of the stock Ubuntu Server
# baseline onto the 64 GB USB. The pinned installer ISO runs in a KVM guest
# whose only disk is a raw IMAGE FILE on the host's NVMe; the finished image is
# then copied to the stick in one sequential pass. (Installing straight onto the
# stick was tried first: its small-random-write speed (~0.85 MB/s) would have
# taken 4+ hours; sequential writes run at ~8.5 MB/s.) Uses autoinstall
# (baseline/autoinstall/user-data.in) so there are no manual steps.
#
# Needs: host/install-usb-access.sh run once (user can write the stick),
#        cached ISO from baseline/phase0-prep.sh, qemu, OVMF, bsdtar, openssl.
#        cache/wifi.env with WIFI_SSID=... and WIFI_PASSWORD=... (gitignored; hotspot
#        for remote access), ~/.ssh/trackc_ed25519.pub (lab SSH key, not in Git).
# Usage: baseline/install-baseline-qemu.sh --wipe <USB serial of 64 GB stick>
#   The serial must be given explicitly as the "yes, erase this stick" check.
# Env: SKIP_INSTALL=1 reuses an existing cache/baseline.img (only re-copies it).
# Output: cache/qemu-install.log (installer serial console),
#         cache/baseline.img (deleted after a verified copy unless KEEP_IMAGE=1),
#         cache/baseline-credentials.txt (generated login, gitignored).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO/build/versions.env"
CACHE="$REPO/cache"; WORK="$CACHE/baseline-install"; HTTP_PORT=8642
IMG="$CACHE/baseline.img"; IMG_GIB=27   # 1 GiB ESP + 25 GiB root + slack
CRED="$CACHE/baseline-credentials.txt"; LOG="$CACHE/qemu-install.log"
SERIAL_EXPECTED="03018820042024224003"   # 64 GB SanDisk Cruzer Blade

[[ ${1:-} == --wipe && ${2:-} == "$SERIAL_EXPECTED" ]] \
  || { echo "usage: $0 --wipe $SERIAL_EXPECTED" >&2; exit 1; }

DEV=$(readlink -f "/dev/disk/by-id/usb-SanDisk_Cruzer_Blade_${SERIAL_EXPECTED}-0:0")
[[ -b $DEV && $(lsblk -dno TRAN "$DEV") == usb ]] || { echo "64 GB stick not found" >&2; exit 1; }
[[ -w $DEV ]] || { echo "$DEV not writable: run 'sudo host/install-usb-access.sh' once" >&2; exit 1; }
if lsblk -no MOUNTPOINT "$DEV" | grep -q .; then echo "$DEV has mounted partitions; unmount first" >&2; exit 1; fi
echo "Target: $DEV  $(lsblk -dno SIZE,MODEL,SERIAL,TRAN "$DEV")"

if [[ ${SKIP_INSTALL:-0} != 1 ]]; then
ISO="$CACHE/$UBUNTU_BASELINE_ISO"
echo "$UBUNTU_BASELINE_SHA256  $ISO" | sha256sum -c --quiet -

rm -rf "$WORK"; mkdir -p "$WORK/http" "$WORK/stage"
# Installer kernel + initrd straight from the ISO (lets us pass autoinstall args).
bsdtar -xf "$ISO" -C "$WORK" casper/vmlinuz casper/initrd

# Generated login for the baseline (never committed).
if [[ ! -f $CRED ]]; then
  printf 'user=trackc\npassword=%s\n' "$(openssl rand -base64 12 | tr -d '/+=')" > "$CRED"
  chmod 600 "$CRED"
fi
PASS=$(sed -n 's/^password=//p' "$CRED")
HASH=$(openssl passwd -6 "$PASS")

HTTP="http://10.0.2.2:$HTTP_PORT"
sed -e "s|__PASSWORD_HASH__|$HASH|" -e "s|__HTTP__|$HTTP|g" \
  "$REPO/baseline/autoinstall/user-data.in" > "$WORK/http/user-data"
cp "$REPO/baseline/autoinstall/meta-data" "$WORK/http/meta-data"
: > "$WORK/http/vendor-data"   # cloud-init polls for it; empty = none
# Prefetched .debs (baseline/prefetch-debs.sh), served to the VM over the local link.
ln -s "$CACHE/debs" "$WORK/http/debs"
( cd "$CACHE/debs" && ls -1 -- *.deb 2>/dev/null ) > "$WORK/http/debs.txt" || true
echo "Seeding $(wc -l < "$WORK/http/debs.txt") prefetched .debs"

cp "$REPO/build/versions.env" "$REPO/baseline/install-nvidia-stack.sh" \
   "$REPO/baseline/phase0-gate.sh" "$REPO/baseline/trackc-phase0-gate.service" \
   "$REPO/benchmark/samples/vector_add.cu" "$WORK/stage/"
cp "$REPO/baseline/install-remote-access.sh" "$WORK/stage/"
cp "$HOME/.ssh/trackc_ed25519.pub" "$WORK/stage/authorized_keys"
# shellcheck source=/dev/null
source "$CACHE/wifi.env"
: "${WIFI_SSID:?set in cache/wifi.env}" "${WIFI_PASSWORD:?set in cache/wifi.env}"
python3 - "$WIFI_SSID" "$WIFI_PASSWORD" > "$WORK/stage/60-trackc-wifi.yaml" <<'PY'
import json, sys
ssid, pw = sys.argv[1], sys.argv[2]
# JSON strings are valid YAML scalars, so quoting is always safe.
print(f'''network:
  version: 2
  wifis:
    wlan:
      match: {{name: "wl*"}}
      dhcp4: true
      optional: true
      access-points:
        {json.dumps(ssid)}: {{password: {json.dumps(pw)}}}''')
PY
tar -C "$WORK/stage" -cf "$WORK/http/stage.tar" .

python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 --directory "$WORK/http" \
  > "$WORK/http.log" 2>&1 &
HTTP_PID=$!
trap 'kill $HTTP_PID 2>/dev/null || true; rm -rf "$WORK/stage" "$WORK/http/stage.tar"' EXIT

rm -f "$IMG"; truncate -s "${IMG_GIB}G" "$IMG"
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$WORK/vars.fd"
: > "$LOG"
echo "Installing (serial console -> $LOG). Expect 30-60 min (slow USB writes + CUDA download)."
# cache=unsafe: dpkg's many fsyncs go to the page cache; the image is synced after.
qemu-system-x86_64 \
  -machine q35,accel=kvm -cpu host -smp 8 -m 8G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file="$WORK/vars.fd" \
  -drive file="$IMG",format=raw,if=none,id=usb64,cache=unsafe,discard=unmap \
  -device virtio-blk-pci,drive=usb64,serial=TRACKC64 \
  -cdrom "$ISO" \
  -kernel "$WORK/casper/vmlinuz" -initrd "$WORK/casper/initrd" \
  -append "autoinstall ds=nocloud-net;s=$HTTP/ console=ttyS0,115200 ---" \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -display none -serial file:"$LOG" -no-reboot

sync "$IMG"
kill $HTTP_PID 2>/dev/null || true
fi  # SKIP_INSTALL

# Did the install (incl. our late-commands) finish? The last late-command writes
# /var/lib/trackc/esp-listing.txt into the root fs (partition 2 of the image).
off=$(partx -g -o START -n 2 "$IMG" | tr -d ' ')
debugfs -R "stat /var/lib/trackc/esp-listing.txt" "$IMG?offset=$((off*512))" 2>/dev/null | grep -q '^Inode:' \
  || { echo "Install did NOT complete (marker file missing). See $LOG" >&2; exit 1; }
echo "Install complete inside image."

# Sequential copy to the stick. conv=sparse skips all-zero blocks (unused space),
# the same idea as bmaptool; filesystems never read their free blocks.
echo "Copying image to $DEV (sequential, only used blocks)..."
dd if="$IMG" of="$DEV" bs=4M conv=sparse,fsync oflag=direct status=progress
sync
# The image's backup GPT sits at 27 GiB; move it to the real end of the stick.
sfdisk --relocate gpt-bak-std "$DEV"
partx -u "$DEV" 2>/dev/null || true; sleep 2
# Verify: filesystem check (read-only) of the root partition on the stick.
ROOTP="${DEV}2"
e2fsck -fn "$ROOTP" && echo "Root filesystem on $ROOTP verified clean."
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEV"
[[ ${KEEP_IMAGE:-0} == 1 ]] || { rm -f "$IMG"; echo "Removed $IMG"; }
echo "Done. Login: $CRED"
