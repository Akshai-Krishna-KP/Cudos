# Stock baseline: Ubuntu Server 24.04.5 onto the 64 GB USB (automated)

The baseline is installed **unattended** from the CachyOS host. No installer screens.

1. One-time host prep (sudo): `sudo host/install-usb-access.sh`, a udev rule that lets your user write the two project sticks (matched by USB serial) and nothing else.
2. Create `cache/wifi.env` from `baseline/wifi.env.example` (phone hotspot) and an SSH key `ssh-keygen -t ed25519 -N '' -f ~/.ssh/trackc_ed25519`.
3. `baseline/phase0-prep.sh`: downloads and verifies the pinned ISO (`build/versions.env`).
4. `baseline/install-baseline-qemu.sh --wipe 03018820042024224003`: boots the installer ISO in a KVM guest whose only disk is the 64 GB stick and runs `autoinstall/user-data.in`:
   - GPT: 1 GiB ESP, 25 GiB ext4 `/`, ~31 GiB left free for the custom image. No LVM. Otherwise stock defaults.
   - `late-commands` run `install-nvidia-stack.sh` (driver, CUDA toolkit, cuDNN, container toolkit, Podman; pinned versions), build `benchmark/samples/vector_add.cu` for sm_89, install the Phase 0 gate service, and add the removable UEFI loader `EFI/BOOT/BOOTX64.EFI` (no `fbx64.efi`, so the laptop's NVRAM is never written).
   - `install-remote-access.sh` adds lab-only access: key-only SSH (user `trackc`), hotspot Wi-Fi, mDNS `baseline.local`, NOPASSWD sudo.
   - Login is generated into `cache/baseline-credentials.txt` (gitignored).
5. Hardware gate: boot the 64 GB stick on Laptop 2 (F12 → USB). `trackc-phase0-gate.service` runs `nvidia-smi` + the CUDA sample and writes `/var/lib/trackc/phase0-gate-*.txt`; Laptop 1 fetches it over SSH.

Secure Boot is **off** on Laptop 1 (checked 2026-11-19 via the `SecureBoot` efivar), so the unsigned DKMS modules load.
