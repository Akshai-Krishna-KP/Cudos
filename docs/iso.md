# Live ISO: `trackc-gpu-appliance.iso` (boots on other laptops like a normal OS)

One file, `out/iso/trackc-gpu-appliance.iso` (2.9 GB, checksum in `SHA256SUMS`). Boots on
UEFI PCs and laptops from a USB stick (Rufus "DD image" mode, balenaEtcher, Ventoy or `dd`),
a DVD, or a virtual machine.

## What makes it work on other laptops
* **Full-hardware kernel**: Debian's stock 6.12 kernel with all drivers (storage, USB, NVMe,
  Wi-Fi, input), not the trimmed kernel of our two lab laptops.
* **Signed boot chain, like Debian/Ubuntu live ISOs**: Debian's signed `shim` -> signed GRUB
  -> Debian-signed kernel. It boots with **Secure Boot on or off**. We sign nothing ourselves.
* **Boot menu**: "Lazarus GPU appliance (live)", a variant that shows boot messages, and
  "UEFI firmware settings".
* **Hybrid layout** (Ubuntu's xorriso recipe): a real EFI partition for USB boot and an El
  Torito image for DVD/VM boot; the initramfs finds the medium on CD drives, USB disks and
  their partitions and loop-mounts `live/rootfs.squashfs`.

## GPU and Secure Boot
| Secure Boot | Result |
|---|---|
| **off** | everything works: NVIDIA driver, health check, `cuda-dev`, `lazarus` |
| **on** | the OS boots and works; the Debian-signed kernel refuses our unsigned NVIDIA driver, and the banner says "Secure Boot is ON and blocks the NVIDIA driver". Choose "UEFI firmware settings" in the boot menu and turn Secure Boot off for the GPU. |
| no NVIDIA GPU | the OS works; the banner says so; CUDA needs an NVIDIA GPU |

## Using it
Boot from the stick (F12 / Esc / F9 boot menu, depending on the laptop). Auto-login as
`lazarus` (password `lazarus`). State is kept in RAM: files are lost at power-off unless a
partition labelled `TRACKC_PERSIST` (ext4) exists. For a stick that keeps your work, flash the
`.img` instead (`docs/portable-image.md`). The first `cuda-dev` unpacks the 3.6 GB toolkit into
RAM (8 GB of RAM or more recommended).

## Build and test
```
build/builder.sh build/rootfs/build-rootfs.sh portable debian-iso
build/builder.sh build/image/build-iso.sh
test/iso-smoke.sh            # QEMU/UEFI: as DVD and as USB stick
```

## Tested
QEMU/KVM with UEFI (OVMF), 2026-11-21 (`docs/results/iso/`): as DVD and as USB stick:
signed shim + GRUB menu, boot, read-only self-test PASS, auto-login, banner. Every boot in
which the emulated firmware started the medium succeeded; QEMU's emulated USB sometimes stalls
inside the firmware before handing over (the test retries and reports it). Secure Boot ON
could not be tested in the emulator (no Microsoft keys enrolled) and real-hardware boots of
this ISO are still to be done.
