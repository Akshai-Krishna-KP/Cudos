#!/usr/bin/env bash
# build-iso.sh: live ISO of the portable variant. Runs INSIDE the builder container.
#   UEFI boot: El Torito EFI image + GPT-appended ESP (hybrid: works as CD/DVD, in a VM, or
#   written to a USB stick with dd/Rufus/Ventoy). The ESP holds the UKI as BOOTX64.EFI with
#   cmdline "root=/dev/loop0 trackc.live": the initramfs (scripts/local-top/trackc-live)
#   mounts the ISO (label TRACKC_LIVE) and loop-mounts live/rootfs.squashfs.
#   State is in RAM (volatile) unless a TRACKC_PERSIST partition exists. The cuda-dev
#   toolkit archive is on the ISO (images/), so cuda-dev works on the live system.
# Usage: build/builder.sh build/rootfs/build-rootfs.sh portable trackc
#        build/builder.sh build/image/build-iso.sh
# Output: out/iso/trackc-gpu-appliance.iso + SHA256SUMS
set -euo pipefail
SRC=/src; R=$SRC/out/rootfs-portable; O=$SRC/out/iso; T=$O/tree
source "$SRC/build/versions.env"; : "${SOURCE_DATE_EPOCH:?}"
rm -rf "$O"; mkdir -p "$T/live" "$T/images" "$T/EFI/BOOT"
KVER=$(ls "$R/lib/modules" | sort -V | tail -1)
CMDLINE="root=/dev/loop0 rootfstype=squashfs ro trackc.live console=ttyS0,115200 console=tty0 quiet loglevel=3 modprobe.blacklist=nouveau systemd.gpt_auto=0 panic=10"
ukify build --linux="$R/boot/vmlinuz-$KVER" --initrd="$R/boot/initrd.img-$KVER" \
  --cmdline="$CMDLINE" --os-release="@$R/etc/os-release" --uname="$KVER" --output="$O/trackc-live.efi"
mksquashfs "$R" "$T/live/rootfs.squashfs" -noappend -comp zstd -Xcompression-level 19 -b 1M \
  -reproducible -wildcards -e 'boot/*' -quiet
cp "$SRC/out/trackc-cuda-dev.tar" "$T/images/"
cp "$O/trackc-live.efi" "$T/EFI/BOOT/BOOTX64.EFI"
cp "$SRC/overlay/esp-portable/README.txt" "$T/README.txt"
# EFI system partition image for El Torito / the appended GPT partition.
efi_kib=$(( ($(stat -c %s "$O/trackc-live.efi") / 1024) + 4096 ))
mkfs.vfat -C -n TRACKC_EFI -i 7C0FFEE1 --invariant "$O/efiboot.img" "$efi_kib" >/dev/null
mmd -i "$O/efiboot.img" ::/EFI ::/EFI/BOOT
mcopy -i "$O/efiboot.img" -m "$O/trackc-live.efi" ::/EFI/BOOT/BOOTX64.EFI
find "$T" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
xorriso -as mkisofs -quiet -iso-level 3 -J -joliet-long -r -V TRACKC_LIVE \
  -append_partition 2 0xef "$O/efiboot.img" -appended_part_as_gpt \
  -e --interval:appended_partition_2:all:: -no-emul-boot \
  -o "$O/trackc-gpu-appliance.iso" "$T"
rm -rf "$T" "$O/efiboot.img"
(cd "$O" && sha256sum trackc-gpu-appliance.iso > SHA256SUMS)
ls -l "$O"
