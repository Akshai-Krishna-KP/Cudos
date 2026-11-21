# Licence inventory: Track C GPU appliance

Every component that ships in the custom image, with licence and whether it is open
source. The full Debian package list with versions is generated at build time
(`out/rootfs-<variant>-packages.tsv`, each package's `/usr/share/doc/*/copyright` is kept
in the image). This file lists the groups and every **proprietary** item with its justification.

## Open source

| Component | Version | Licence | Source |
|---|---|---|---|
| Debian 13 "trixie" base (minbase, systemd, udev, kmod, initramfs-tools, busybox, zstd, procps) | snapshot 20261114T202348Z | GPL-2+/LGPL/MIT/BSD mix (per package) | https://snapshot.debian.org |
| Linux kernel (Debian `linux-image-amd64`) | 6.12.117-1 | GPL-2.0 | https://kernel.org, Debian |
| NVIDIA open GPU kernel modules (`nvidia-kernel-open-dkms`, built at image build time) | 620.70.06 | Dual MIT / GPL-2.0 | https://github.com/NVIDIA/open-gpu-kernel-modules |
| NVIDIA Container Toolkit, libnvidia-container | 1.20.2 | Apache-2.0 | https://github.com/NVIDIA/nvidia-container-toolkit |
| Podman, crun, conmon, netavark, uidmap | Debian trixie | Apache-2.0 / GPL-2+ / LGPL-2.1+ | Debian |
| nftables | Debian trixie | GPL-2.0 | Debian |
| D-Bus (system bus for nvidia-powerd, systemd) | 1.16.2 | GPL-2+ / AFL-2.1 | Debian |
| Benchmark `benchmark/src/trackc_bench.cu`, all scripts in this repo | this repo | (project licence) | this repo |
| Benchmark container base: Ubuntu 24.04 (`ubuntu@sha256:73b9...`) | 24.04 | per package, open source | https://hub.docker.com/_/ubuntu |
| DEV image only: OpenSSH, wpa_supplicant, sudo, iproute2 | Debian trixie | BSD / BSD / ISC-style / GPL-2 | Debian |

## Proprietary (redistributable binaries, NVIDIA)

| Component | Version | Where | Why it is needed | Redistribution |
|---|---|---|---|---|
| `libcuda1` (CUDA driver API, `libcuda.so`) + `libnvidia-ptxjitcompiler1`, `libnvidia-gpucomp`, `libnvidia-pkcs11-openssl3` | 620.70.06 | rootfs | Every CUDA program talks to the GPU through libcuda; no open replacement exists for CUDA. | NVIDIA driver licence permits redistribution of the unmodified driver components; shipped unmodified from NVIDIA's apt repo. |
| `libnvidia-ml1` (NVML) | 620.70.06 | rootfs | Live GPU metrics (temperature, power, clocks) and CDI generation. | as above |
| `firmware-nvidia-gsp` (GSP firmware) | 620.70.06 | rootfs `/lib/firmware/nvidia` | Required by the open kernel modules on Ada GPUs: the GPU System Processor runs this firmware. | as above (firmware redistributable) |
| `nvidia-smi` binary (extracted from `nvidia-driver-cuda`, not installed as a package) | 620.70.06 | rootfs `/usr/bin` | Standard tool for the demo and measurements; only the binary is kept to avoid ~20 unneeded libraries. Recorded here because it is a non-dpkg component. | as above |
| `nvidia-powerd` (Dynamic Boost daemon) | 620.70.06 | rootfs | Without it the laptop GPU stays in lower P-states: ~12% less bandwidth (measured, `docs/results/phase8/powerd-experiment-baseline.txt`). | as above |
| `nvidia-modprobe` | 620.70.06 | rootfs | Creates `/dev/nvidia*` nodes for unprivileged users. (Source is GPL-2.0 on GitHub; packaged by NVIDIA.) | open source |
| cuBLAS (`libcublas.so.13`, `libcublasLt.so.13`) | CUDA 13.5 (13.10.0.20) | benchmark container only | SGEMM benchmark. | CUDA EULA Attachment A lists cuBLAS runtime libraries as redistributable with applications. |
| CUDA runtime (`cudart`, statically linked into `trackc_bench`) | 13.5.37 | benchmark container | CUDA runtime API. | CUDA EULA Attachment A: redistributable. |

Not shipped: CUDA toolkit (nvcc, headers, static libs), cuDNN (benchmark uses cuBLAS + custom kernels; cuDNN would add ~2 GB), NVIDIA X/GL/Vulkan/video libraries.

Secure Boot: the NVIDIA modules are built unsigned in this version; Secure Boot must be off (documented limitation, signing is future work).

## Installed by the user at runtime (not shipped in any image)

`lazarus-install` downloads packages directly from NVIDIA's official CUDA repository (and
dependencies from the Ubuntu archive) onto the user's own stick, under NVIDIA's own licence
terms (CUDA EULA, cuDNN/NCCL/cuTENSOR SLAs) that the user accepts by installing. The project
does not redistribute them; the image ships only the repository key (pinned) and a curated
list of package names (`overlay/rootfs-dev/usr/share/trackc/cuda-dev/libraries.txt`).
The `cuda-dev` toolkit archive (CUDA 13.5 nvcc, cudart, cuBLAS, cuRAND, cuFFT, NVRTC,
nvJitLink, NVTX; Ubuntu 24.04 base) is copied onto the stick's persist partition; it is
built from unmodified NVIDIA packages (CUDA EULA: redistributable components plus the
toolkit for development use by the stick's owner).
