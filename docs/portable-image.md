# The portable image: `trackc-gpu-appliance.img`

One file you can flash to any USB stick of **8 GB or more** and boot on any UEFI PC or
laptop with an NVIDIA GPU (Secure Boot off). No lab secrets inside: no Wi-Fi passwords, no
SSH keys, no host keys, root locked.

Build: `build/builder.sh build/rootfs/build-rootfs.sh portable trackc && build/builder.sh build/image/build-image.sh portable`
Output: `out/portable/trackc-gpu-appliance.img` (3.6 GB), `.img.zst` (2.7 GB, for download), `SHA256SUMS`.

## Flash it
* Windows: Rufus or balenaEtcher, select the `.img` (or `.img.zst` with Etcher), "DD image" mode.
* Linux/macOS: `zstd -dc trackc-gpu-appliance.img.zst | sudo dd of=/dev/<usb-stick> bs=4M conv=fsync status=progress`
  (check the device name with `lsblk` first: everything on it is erased).

## What happens on first boot
1. The firmware boots `EFI/BOOT/BOOTX64.EFI` directly: our kernel + initramfs in one UKI, no GRUB.
2. The persist partition grows to the end of the stick (`trackc-grow-persist`).
3. The GPU is detected and configured (driver, persistence mode, Dynamic Boost, CDI), then a
   one-time CUDA health check runs; the result appears in the banner on screen.
4. The console logs in automatically as user **gpu** (no sudo). `cuda-dev` works immediately:
   the CUDA 13.5 toolkit archive is already on the persist partition (first use unpacks it, ~2 min).

## Optional: network and SSH
Edit the stick's small FAT partition (visible from Windows, it holds `README.txt`):
* `trackc/authorized_keys`: your SSH public key. SSH starts, key-only, user `gpu`, port 22
  opened in the firewall; host keys are generated on that stick and kept on it.
* `trackc/wifi.txt`: two lines, `SSID=...` and `PASSWORD=...`.
Wired Ethernet gets DHCP without any file.

## Partitions
| # | Label | Size in the image | Content |
|---|---|---|---|
| 1 | esp | 256 MiB | UKI as `EFI/BOOT/BOOTX64.EFI`, `README.txt`, `trackc/` settings folder |
| 2 | trackc-root | 771 MiB | read-only squashfs root |
| 3 | trackc-persist (TRACKC_PERSIST) | 2.3 GiB, grows to the stick's end | `/var`, `/home` overlays, container storage, cuda-dev toolkit, `~/cuda` |
