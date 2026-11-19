#!/usr/bin/env bash
# build-image.sh: turn out/rootfs into a bootable GPT disk image. Runs INSIDE
# the builder container, no root on the host needed (no loop devices).
#   p1 ESP (FAT32)   EFI/BOOT/BOOTX64.EFI = Unified Kernel Image (kernel+initrd+cmdline)
#   p2 trackc-root   squashfs (zstd), read-only root
#   p3 trackc-persist ext4 labelled TRACKC_PERSIST (writable state)
# Usage: build/builder.sh build/image/build-image.sh
# Output: out/trackc.efi, out/rootfs.squashfs, out/disk.img
set -euo pipefail
SRC=/src; O=$SRC/out; R=$O/rootfs
source "$SRC/build/versions.env"
: "${SOURCE_DATE_EPOCH:?}"
ESP_MIB=256; PERSIST_MIB=512

KVER=$(ls "$R/lib/modules" | sort -V | tail -1)
CMDLINE="root=PARTLABEL=trackc-root rootfstype=squashfs ro console=tty0 console=ttyS0,115200 panic=10"
echo "kernel $KVER"

# 1. UKI: one signed-able EFI binary, no bootloader needed (OVMF/laptop firmware boots it directly).
ukify build \
  --linux="$R/boot/vmlinuz-$KVER" --initrd="$R/boot/initrd.img-$KVER" \
  --cmdline="$CMDLINE" --os-release="@$R/etc/os-release" --uname="$KVER" \
  --output="$O/trackc.efi"

# 2. squashfs root. /boot is excluded: kernel+initrd live in the UKI on the ESP.
rm -f "$O/rootfs.squashfs"
mksquashfs "$R" "$O/rootfs.squashfs" -noappend -comp zstd -Xcompression-level 19 -b 1M \
  -reproducible -mkfs-time "$SOURCE_DATE_EPOCH" -all-time "$SOURCE_DATE_EPOCH" \
  -wildcards -e 'boot/*' -quiet

# 3. ESP image (FAT32, fixed volume id for reproducibility).
rm -f "$O/esp.img"
mkfs.vfat -C -F 32 -n ESP -i 7C0FFEE0 --invariant "$O/esp.img" $((ESP_MIB * 1024)) >/dev/null
mmd -i "$O/esp.img" ::/EFI ::/EFI/BOOT
mcopy -i "$O/esp.img" -m "$O/trackc.efi" ::/EFI/BOOT/BOOTX64.EFI

# 4. persist image (ext4, fixed UUID + hash seed; E2FSPROGS_FAKE_TIME for timestamps).
rm -f "$O/persist.img"
E2FSPROGS_FAKE_TIME=$SOURCE_DATE_EPOCH mkfs.ext4 -q -L TRACKC_PERSIST \
  -U 7c0ffee0-0000-4000-8000-000000000003 -E hash_seed=7c0ffee0-0000-4000-8000-0000000000aa,root_owner=0:0 \
  "$O/persist.img" "${PERSIST_MIB}M"

# 5. GPT disk: sizes in 1 MiB units, 1 MiB alignment, fixed GUIDs.
sq_mib=$(( ($(stat -c %s "$O/rootfs.squashfs") + 1048575) / 1048576 + 16 ))
total_mib=$(( 1 + ESP_MIB + sq_mib + PERSIST_MIB + 1 ))
rm -f "$O/disk.img"; truncate -s "${total_mib}M" "$O/disk.img"
sgdisk -q -o -U 7c0ffee0-0000-4000-8000-000000000000 \
  -n "1:1M:+${ESP_MIB}M"     -t 1:ef00 -c 1:esp            -u 1:7c0ffee0-0000-4000-8000-000000000001 \
  -n "2:0:+${sq_mib}M"       -t 2:8300 -c 2:trackc-root    -u 2:7c0ffee0-0000-4000-8000-000000000002 \
  -n "3:0:+${PERSIST_MIB}M"  -t 3:8300 -c 3:trackc-persist -u 3:7c0ffee0-0000-4000-8000-000000000003 \
  "$O/disk.img"
put() { dd if="$1" of="$O/disk.img" bs=1M seek="$2" conv=notrunc,sparse status=none; }
put "$O/esp.img" 1
put "$O/rootfs.squashfs" $((1 + ESP_MIB))
put "$O/persist.img" $((1 + ESP_MIB + sq_mib))
sgdisk -p "$O/disk.img" | tail -4
ls -lh "$O/trackc.efi" "$O/rootfs.squashfs" "$O/disk.img"
