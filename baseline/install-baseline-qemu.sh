#!/usr/bin/env bash
# install-baseline-qemu.sh: unattended install of the stock Ubuntu Server
# baseline onto the 64 GB USB, by running the pinned installer ISO in a KVM
# guest with the USB stick passed through as its only disk. Uses autoinstall
# (baseline/autoinstall/user-data.in) so there are no manual steps.
#
# Needs: host/install-usb-access.sh run once (user can write the stick),
#        cached ISO from baseline/phase0-prep.sh, qemu, OVMF, bsdtar, openssl.
# Usage: baseline/install-baseline-qemu.sh --wipe <USB serial of 64 GB stick>
#   The serial must be given explicitly as the "yes, erase this stick" check.
# Output: cache/qemu-install.log (installer serial console),
#         cache/baseline-credentials.txt (generated login, gitignored).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO/build/versions.env"
CACHE="$REPO/cache"; WORK="$CACHE/baseline-install"; HTTP_PORT=8642
SERIAL_EXPECTED="03018820042024224003"   # 64 GB SanDisk Cruzer Blade

[[ ${1:-} == --wipe && ${2:-} == "$SERIAL_EXPECTED" ]] \
  || { echo "usage: $0 --wipe $SERIAL_EXPECTED" >&2; exit 1; }

DEV=$(readlink -f "/dev/disk/by-id/usb-SanDisk_Cruzer_Blade_${SERIAL_EXPECTED}-0:0")
[[ -b $DEV && $(lsblk -dno TRAN "$DEV") == usb ]] || { echo "64 GB stick not found" >&2; exit 1; }
[[ -w $DEV ]] || { echo "$DEV not writable: run 'sudo host/install-usb-access.sh' once" >&2; exit 1; }
if lsblk -no MOUNTPOINT "$DEV" | grep -q .; then echo "$DEV has mounted partitions; unmount first" >&2; exit 1; fi
echo "Target: $DEV  $(lsblk -dno SIZE,MODEL,SERIAL,TRAN "$DEV")"

ISO="$CACHE/$UBUNTU_BASELINE_ISO"
echo "$UBUNTU_BASELINE_SHA256  $ISO" | sha256sum -c --quiet -

rm -rf "$WORK"; mkdir -p "$WORK/http" "$WORK/stage"
# Installer kernel + initrd straight from the ISO (lets us pass autoinstall args).
bsdtar -xf "$ISO" -C "$WORK" casper/vmlinuz casper/initrd

# Generated login for the baseline (never committed).
CRED="$CACHE/baseline-credentials.txt"
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
cp "$REPO/build/versions.env" "$REPO/baseline/install-nvidia-stack.sh" \
   "$REPO/baseline/phase0-gate.sh" "$REPO/baseline/trackc-phase0-gate.service" \
   "$REPO/benchmark/samples/vector_add.cu" "$WORK/stage/"
tar -C "$WORK/stage" -cf "$WORK/http/stage.tar" .

python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 --directory "$WORK/http" \
  > "$WORK/http.log" 2>&1 &
HTTP_PID=$!
trap 'kill $HTTP_PID 2>/dev/null || true' EXIT

cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$WORK/vars.fd"
LOG="$CACHE/qemu-install.log"; : > "$LOG"
echo "Installing (serial console -> $LOG). Expect 30-60 min (slow USB writes + CUDA download)."
# cache=unsafe: host page cache absorbs dpkg's many small fsyncs on the slow
# stick; we sync + flush the device explicitly once QEMU exits.
qemu-system-x86_64 \
  -machine q35,accel=kvm -cpu host -smp 8 -m 8G \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file="$WORK/vars.fd" \
  -drive file="$DEV",format=raw,if=none,id=usb64,cache=unsafe,discard=unmap \
  -device virtio-blk-pci,drive=usb64,serial=TRACKC64 \
  -cdrom "$ISO" \
  -kernel "$WORK/casper/vmlinuz" -initrd "$WORK/casper/initrd" \
  -append "autoinstall ds=nocloud-net;s=$HTTP/ console=ttyS0,115200 ---" \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -display none -serial file:"$LOG" -no-reboot

echo "QEMU exited; flushing writes to $DEV..."
sync; blockdev --flushbufs "$DEV" 2>/dev/null || true; sync
lsblk -o NAME,SIZE,FSTYPE,LABEL "$DEV"
echo "Done. Login: $CRED"
