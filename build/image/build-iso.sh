#!/usr/bin/env bash
# build-iso.sh: live ISO of the portable appliance that boots on other laptops like a normal
# OS. Runs INSIDE the builder container.
#   * Kernel: Debian's stock 6.12 kernel (all drivers, signed by Debian), not our trimmed
#     laptop kernel: unknown laptops need storage/USB/controller drivers we trimmed away.
#   * Boot: Debian's signed shim -> signed GRUB (gcdx64, the CD/USB variant) -> signed kernel,
#     the same chain Debian live ISOs use, so it boots with Secure Boot on or off. We sign
#     nothing ourselves. With Secure Boot ON the kernel refuses our unsigned NVIDIA modules:
#     the OS works, GPU features need Secure Boot OFF (the banner says so).
#   * Hybrid UEFI ISO (xorriso): DVD, VM, or written to a USB stick (dd / Rufus DD / Etcher /
#     Ventoy). The initramfs (overlay/iso/.../local-top/trackc-live) finds the medium and
#     loop-mounts live/rootfs.squashfs. State in RAM unless a TRACKC_PERSIST partition exists.
# Usage: build/builder.sh build/rootfs/build-rootfs.sh portable debian-iso
#        build/builder.sh build/image/build-iso.sh
# Output: out/iso/trackc-gpu-appliance.iso + SHA256SUMS
set -euo pipefail
SRC=/src; R=$SRC/out/rootfs-portable; O=$SRC/out/iso; T=$O/tree
[[ -f $R/etc/initramfs-tools/scripts/local-top/trackc-live ]] \
  || { echo "build the rootfs for the ISO first: build-rootfs.sh portable debian-iso" >&2; exit 1; }
source "$SRC/build/versions.env"; : "${SOURCE_DATE_EPOCH:?}"
rm -rf "$O"; mkdir -p "$T/live" "$T/images" "$T/EFI/BOOT" "$T/boot/grub" "$T/.disk"
KVER=$(ls "$R/lib/modules" | sort -V | tail -1)

# 1. Debian's signed boot chain (pinned snapshot): shim, MOK manager, GRUB for CD/USB media.
W=$(mktemp -d); (cd "$W" && apt-get -qq update && apt-get -qq download shim-signed shim-helpers-amd64-signed grub-efi-amd64-signed) >/dev/null
for d in "$W"/*.deb; do dpkg-deb -x "$d" "$W/x"; done
cp "$W/x/usr/lib/shim/shimx64.efi.signed"                 "$T/EFI/BOOT/BOOTX64.EFI"
cp "$W/x/usr/lib/shim/mmx64.efi.signed"                   "$T/EFI/BOOT/mmx64.efi"
cp "$W/x/usr/lib/grub/x86_64-efi-signed/gcdx64.efi.signed" "$T/EFI/BOOT/grubx64.efi"
rm -rf "$W"

# 2. Kernel + initramfs (Debian-signed kernel; initramfs has the live-medium finder).
cp "$R/boot/vmlinuz-$KVER" "$T/live/vmlinuz"
cp "$R/boot/initrd.img-$KVER" "$T/live/initrd.img"

# 3. GRUB menu. The signed GRUB finds the medium by /.disk/info and reads /boot/grub/grub.cfg.
echo "Lazarus GPU appliance (Track C) live" > "$T/.disk/info"
ARGS="root=/dev/loop0 rootfstype=squashfs ro trackc.live modprobe.blacklist=nouveau systemd.gpt_auto=0"
cat > "$T/boot/grub/grub.cfg" <<EOF
set timeout=5
set default=0
menuentry "Lazarus GPU appliance (live)" {
  linux /live/vmlinuz $ARGS console=ttyS0,115200 console=tty0 quiet loglevel=3
  initrd /live/initrd.img
}
menuentry "Lazarus GPU appliance (live, show boot messages)" {
  linux /live/vmlinuz $ARGS console=ttyS0,115200 console=tty0
  initrd /live/initrd.img
}
menuentry "UEFI firmware settings (turn Secure Boot off for the GPU)" {
  fwsetup
}
EOF
cp "$T/boot/grub/grub.cfg" "$T/EFI/BOOT/grub.cfg"

# 4. System, toolkit, marker, readme.
mksquashfs "$R" "$T/live/rootfs.squashfs" -noappend -comp zstd -Xcompression-level 19 -b 1M \
  -reproducible -wildcards -e 'boot/*' -quiet
cp "$SRC/out/trackc-cuda-dev.tar" "$T/images/"
echo "Track C GPU appliance live medium" > "$T/live/trackc-live.id"   # found by the initramfs
cp "$SRC/overlay/esp-portable/README.txt" "$T/README.txt"

# 5. EFI image inside the ISO + the Debian/Ubuntu hybrid layout (xorriso): -isohybrid-gpt-basdat
#    exposes the EFI image as a GPT partition for USB boot, -partition_offset 16 makes the
#    first partition a readable ISO9660 filesystem so the signed GRUB finds /.disk/info on USB too.
efi_kib=$(( ($(du -sk "$T/EFI" | cut -f1)) + 2048 ))
mkfs.vfat -C -n LAZARUS_EFI -i 7C0FFEE1 --invariant "$T/boot/grub/efi.img" "$efi_kib" >/dev/null
mmd -i "$T/boot/grub/efi.img" ::/EFI ::/EFI/BOOT
mcopy -i "$T/boot/grub/efi.img" -m "$T"/EFI/BOOT/* ::/EFI/BOOT/
find "$T" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
xorriso -as mkisofs -quiet -iso-level 3 -J -joliet-long -r -V TRACKC_LIVE \
  -e boot/grub/efi.img -no-emul-boot -isohybrid-gpt-basdat -partition_offset 16 \
  -o "$O/trackc-gpu-appliance.iso" "$T"
rm -rf "$T" "$O/efiboot.img"
(cd "$O" && sha256sum trackc-gpu-appliance.iso > SHA256SUMS)
echo "kernel $KVER (Debian, signed); boot: shim + signed GRUB"; ls -l "$O"
