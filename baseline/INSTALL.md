# Stock baseline: Ubuntu Server 24.04.5 onto the 64 GB USB (automated)

The baseline is installed **unattended** from the CachyOS host. No installer screens.

1. One-time host prep (sudo): `sudo host/install-usb-access.sh`, a udev rule that lets your user write the two project sticks (matched by USB serial) and nothing else.
2. `baseline/phase0-prep.sh`: downloads and verifies the pinned ISO (`build/versions.env`).
3. `baseline/install-baseline-qemu.sh --wipe 03018820042024224003`: boots the installer ISO in a KVM guest whose only disk is the 64 GB stick and runs `autoinstall/user-data.in`:
   - GPT: 1 GiB ESP, 25 GiB ext4 `/`, ~31 GiB left free for the custom image. No LVM. Otherwise stock defaults.
   - `late-commands` run `install-nvidia-stack.sh` (driver, CUDA toolkit, cuDNN, container toolkit, Podman; pinned versions), build `benchmark/samples/vector_add.cu` for sm_89, install the Phase 0 gate service, and add the removable UEFI loader `EFI/BOOT/BOOTX64.EFI` (no `fbx64.efi`, so the laptop's NVRAM is never written).
   - Login is generated into `cache/baseline-credentials.txt` (gitignored).
4. Hardware gate: boot the 64 GB stick on the laptop (F12 → USB). `trackc-phase0-gate.service` runs `nvidia-smi` + the CUDA sample, writes `/var/lib/trackc/phase0-gate-*.txt`, and powers off (while `/etc/trackc/auto-poweroff` exists). Back on CachyOS the result is read from the stick.

Secure Boot is **off** on Laptop 1 (checked 2026-11-19 via the `SecureBoot` efivar), so the unsigned DKMS modules load.
