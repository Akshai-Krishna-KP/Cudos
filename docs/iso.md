# Live ISO: `trackc-gpu-appliance.iso`

UEFI-bootable live ISO of the portable appliance (no lab secrets). Boots from a USB stick
(written with Rufus "DD mode", balenaEtcher, Ventoy or `dd`), a DVD, or a VM. Secure Boot off.

Build (on the build host):
```
build/kernel/run.sh iso                                          # ISO kernel -> out/kernel-iso
build/builder.sh build/rootfs/build-rootfs.sh portable trackc-iso
build/builder.sh build/image/build-iso.sh                        # -> out/iso/trackc-gpu-appliance.iso
test/iso-smoke.sh                                                # QEMU: as CD-ROM and as USB stick
```
Output: `out/iso/trackc-gpu-appliance.iso` (2.8 GB) and `SHA256SUMS`.

## How it boots
1. Firmware loads `EFI/BOOT/BOOTX64.EFI` (our kernel + initramfs, cmdline `root=/dev/loop0 trackc.live`).
2. The initramfs (`overlay/iso/.../local-top/trackc-live`) loads CD/SATA/USB/virtio drivers,
   searches CD drives, disks and their partitions for the ISO (marker `live/trackc-live.id`),
   mounts it and attaches `live/rootfs.squashfs` read-only as the root.
3. The usual appliance boot follows: GPU auto-configuration, health-check benchmark, banner,
   auto-login as `gpu`, `cuda-dev` (toolkit read from `images/` on the ISO).

## Differences from the `.img`
* State lives in RAM: changes and `~/cuda` are lost at power-off, unless a partition labelled
  `TRACKC_PERSIST` (ext4) exists on any disk, which is then used for `/var` and `/home`.
* First `cuda-dev` unpacks the 3.6 GB toolkit into RAM: needs about 8 GB of RAM or more.
* SSH / Wi-Fi files (`trackc/`) are not read from the ISO (read-only); use the `.img` for that.
* Uses its own kernel flavour (`build/kernel/trackc-iso.config`: + iso9660, loop, CD, SATA/IDE,
  USB 2.0/1.1, virtio-scsi), so it also boots on machines other than our two laptops.

## Tested
QEMU/KVM with UEFI (OVMF), 2026-11-20 (`docs/results/iso/`): as SATA CD-ROM and as USB mass
storage: boot to login in 12 s, read-only self-test PASS (squashfs root, overlays, mount flags,
volatile state). Not yet booted on real hardware or with a GPU from the ISO.
