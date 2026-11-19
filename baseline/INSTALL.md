# Stock baseline: Ubuntu Server 24.04.5 onto the 64 GB USB

The only manual (interactive) step in the project. Everything after first boot is scripted in `baseline/`.

**Media:** installer = 8 GB USB (ISO pinned in `build/versions.env`, written by `phase0-prep.sh`). Target = 64 GB SanDisk Cruzer Blade.
**Machine:** Laptop 1 (Lenovo 83DV). Boot menu: **F12** at power-on (or the Novo pinhole button → Boot Menu).

## Target layout on the 64 GB stick (57.3 GiB)
| # | Size | Format | Mount | Purpose |
|---|---|---|---|---|
| 1 | 1 GiB | FAT32 | `/boot/efi` | ESP, shared by baseline and custom image |
| 2 | 25 GiB | ext4 | `/` | Stock Ubuntu baseline |
| — | ~31 GiB | **leave free** | — | Custom image root + persist; created later by `build/image/` scripts |

Deviation from a fully stock install: no LVM, and free space left on the disk. Both are needed to share the stick with the custom image. Everything else uses installer defaults (including `/swap.img`).

## Steps
1. Plug in **both** sticks. Power on, press **F12**, pick the **8 GB "Flash Disk"** entry (UEFI). Secure Boot may stay on: Ubuntu's shim is signed.
2. *Try or Install Ubuntu Server* → language, keyboard defaults.
3. Type: **Ubuntu Server** (not minimized). Search for third-party drivers: **off** (NVIDIA comes from NVIDIA's repo, scripted).
4. Network: plug Ethernet if possible (`enp7s0`), else join Wi-Fi. Proxy: none. Mirror: default.
5. Storage: **Custom storage layout**.
   - **Only touch the device ~57.3G "SanDisk Cruzer Blade".** Do not edit, format, or select the 476.9G WD NVMe (Windows + CachyOS). If unsure, stop.
   - On the SanDisk: *Reformat* → *Use as boot device* (creates the 1 GiB ESP; if it offers a different size, edit it to 1G).
   - *Add GPT partition* on the free space: size **25G**, ext4, mount `/`.
   - Leave the remaining ~31G as free space.
   - The summary must list only the SanDisk under "used devices". Confirm → *Continue*.
6. Profile: your name, server name `baseline`, user + password (not committed anywhere).
7. Ubuntu Pro: skip. SSH: **Install OpenSSH server: off** (matches our "no SSH by default" policy; baseline is used locally).
8. Featured snaps: select **none**.
9. Wait for install, *Reboot Now*, remove the 8 GB stick when told.
10. Boot the 64 GB stick via **F12**, log in, run `lsblk` and `uname -r` and report the output.

## Known follow-ups (scripted next)
- Ubuntu's grub writes an `ubuntu` UEFI boot entry into the laptop's NVRAM. It does **not** touch the internal ESP. If the laptop starts booting the USB by default, reorder in BIOS (F2) so CachyOS stays first; F12 still reaches the USB.
- The stick may lack the removable fallback loader (`EFI/BOOT/BOOTX64.EFI`), which Laptop 2 needs. A post-install script will add it.
