# Feature: first-boot GPU auto-configuration + SSH CUDA development

Requested by the user on 2026-11-19. Decisions taken the same day. Implemented in Phases 4–6 (not before).

## Goals
1. On first boot the OS detects the NVIDIA GPU and configures the newest LTS driver for it without user action.
2. Users can SSH in and write, compile and run CUDA code.

## Decisions
| Topic | Decision | Rejected alternative (why) |
|---|---|---|
| Driver source | **Prebuilt + signed.** The build picks the newest NVIDIA *LTS/production* branch automatically (`build/nvidia/resolve-latest-lts.sh` reads NVIDIA's repo metadata), records it in `build/versions.env`, builds the open modules against our kernel and signs them. | Compile on device at first boot: breaks reproducibility, needs compiler + headers in the image (+~300 MB), and needs the signing key on the device, which defeats lockdown + `module.sig_enforce`. |
| First boot | `gpu-autoconfig.service` (oneshot, before the benchmark): reads PCI IDs from `/sys/bus/pci/devices/*/` (vendor `0x10de`), maps the device to its architecture, refuses pre-Turing GPUs with a clear message (open modules need Turing+), loads the shipped modules, runs `nvidia-ctk cdi generate`, writes a report to `/var/lib/gpu-autoconfig/`. | |
| Driver updates | Optional `gpu-driver-update`: checks NVIDIA metadata for a newer LTS branch; if newer, downloads **our** prebuilt, signed module + userspace bundle for this exact kernel into the persist partition and switches to it on the next boot; keeps the shipped driver as the fallback. Bundles are produced by the same build scripts. | |
| CUDA development | **Dev container.** `cuda-dev` starts a rootless Podman CUDA *devel* container (nvcc, headers, libs; pinned digest) via CDI, pulled once to `/var/lib/containers` on the persist partition; `~/work` bind-mounted. Root image stays runtime-only. | nvcc on the host: several GB, hurts the 40 % size target. |
| SSH access | **Key file on the USB.** User drops `authorized_keys` on the stick's visible FAT partition; first boot installs it for the non-root `gpu` user. Key-only, no root login, no passwords. Without a key file, `sshd` stays disabled. | One-time on-screen password (weaker, interactive). |

## Impact on the plan
- Hardening item 5 becomes: **SSH off unless a key is provisioned; key-only, no root**; nftables default-deny with only TCP/22 open when SSH is enabled.
- Size budget: adds `openssh-server` + `pciutils`-free detection script (sysfs only); the devel container lives on the persist partition and is reported separately (not part of the read-only image).
- Measurements: report image size with and without the devel container on the medium.
- Licence inventory: the CUDA devel container (proprietary NVIDIA EULA components) must be listed and justified.
