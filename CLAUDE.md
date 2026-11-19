# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Track C CUDA/GPU Application-Specific Linux Distro

## Project in one paragraph
University OS Lab group assignment: **"Application-Specific Linux Distribution for ML, IoT, CUDA and FPGA Platforms"**, **Track C (CUDA/GPU compute)**. We are building a tiny, headless, read-only Linux "GPU appliance" that boots from USB, loads the NVIDIA driver, and auto-starts a containerised CUDA benchmark with live GPU metrics. We then prove it is leaner than a stock distro (size, RAM, boot time, package count, GPU performance).

## How we work together
- **The user guides every step.** Work one phase at a time. Do not jump ahead to later phases.
- **Explain before acting.** Before running anything non-trivial, state what you are about to do and why. Wait for approval on anything destructive, slow (kernel builds), or that changes the plan.
- **Ask when unsure.** Do not guess about hardware, device paths, or decisions listed under "Open questions".
- **Never fabricate results.** Every number in the report (sizes, boot times, RAM, benchmark scores) must come from a script in `measure/` that we actually ran. If something was not measured, say so.
- Keep explanations short and plain. The user is learning this as we go.

## Hard constraints (from the assignment)
1. Build must be **100% reproducible from scripts stored in Git**. No manual, undocumented steps.
2. **Proprietary components** (NVIDIA driver userspace, GSP firmware, CUDA runtime libs, cuDNN) are allowed **only if listed and justified** in the licence inventory. Everything else must be open source.
3. **At least 40% image size reduction** vs. the stock baseline, or a rigorous, documented justification for the shortfall.
4. At least **three concrete security hardening measures**.
5. Read-only root filesystem + overlayfs for writable state.
6. End-to-end demo: CUDA benchmark running on the GPU inside a container/service with live metrics.

## Hardware and lab environment
- **Laptop 1 (primary build and test host):** Intel Core i7 HX, NVIDIA RTX 4050 Laptop (Ada, sm_89), **CachyOS** (dual boot).
  - Host facts: 20 threads, ~23 GB RAM, host driver 620.70.06. Docker and QEMU installed; Podman and f3 to be installed (`sudo pacman -S podman f3`).
  - **Only ~28 GB free on `/home`.** Keep build scratch small and cleanable (kernel `make clean`, prune images); check `df -h` before large steps.
- **Laptop 2 (external validation only):** AMD Ryzen, NVIDIA RTX 4060 Laptop (Ada, sm_89), **Windows 11** (dual boot). **Not available during development.** All Laptop-2 gates are deferred to Phase 8.
- **Media: 64 GB USB** (SanDisk Cruzer Blade, main dev/measurement drive) **+ 8 GB USB** ("Flash Disk", 7.4 GiB).
  - 8 GB: first used as the Ubuntu Server installer stick (Phase 0), later as the release-candidate drive for the graded image (ESP + squashfs root + small persist).
  - 64 GB planned GPT layout:
    1. ESP (~1 GB, shared boot menu for baseline and custom image)
    2. Stock Ubuntu Server 24.04 baseline root (~25 GB)
    3. Custom image: squashfs root, **budget ≤ 8 GB** so the graded image would still fit an 8 GB stick
    4. Persist partition for the custom image (rest)
    Baseline and custom image share one medium, so boot-time comparisons are fair.
- Both GPUs are Ada, so **target sm_89 only**.

## Safety rules (read carefully)
- **NEVER write to internal disks.** All flashing and partitioning targets USB drives only.
- **Before any `dd`, `mkfs`, `parted`, `sgdisk`, `wipefs`, or similar:** run `lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINT`, confirm the target is the intended USB (match size and `TRAN=usb`), and **ask the user to confirm the device path**. Never assume `/dev/sdX`.
- Do not modify the host CachyOS system (bootloader, kernel, drivers, fstab) unless the user explicitly asks. Build inside a **Podman container** so the host stays clean.
- **Laptop 2 / Windows:** back up the BitLocker recovery key before any firmware or Secure Boot change. Never touch Windows partitions.
- No secrets, keys, or personal data in Git. Module-signing keys stay out of the repo (`.gitignore` them; document how to regenerate).
- Do not run long builds, large downloads, or anything requiring `sudo` without telling the user first.

## Architecture decisions (settled unless the user changes them)
| Area | Decision |
|---|---|
| Build system | Script-driven **debootstrap `--variant=minbase`** against a pinned `snapshot.debian.org` date, run in a Podman build container. `mkosi` may be used as a wrapper if helpful. Yocto/Buildroot rejected (CUDA/cuDNN packaging effort, no x86 NVIDIA support). |
| Base distro | Debian stable. Fallback: Ubuntu 24.04 `minbase` if NVIDIA/Debian repo support is a problem. |
| Stock baseline | **Ubuntu Server 24.04 LTS** with the same functionality from NVIDIA's apt repos (driver, full cuda-toolkit, cuDNN, container toolkit, Podman/Docker). |
| Kernel | Upstream kernel.org **LTS**, `localmodconfig` from both laptops then hand-trimmed; config kept as **fragments** in Git. |
| NVIDIA driver | **`nvidia-open`** kernel modules built from source against our kernel; userspace and GSP firmware are proprietary (must be inventoried). |
| CUDA / cuDNN | **Not on the host.** Host has driver + container toolkit only. CUDA runtime lives in a **slim multi-stage container image** (compile with `nvcc -arch=sm_89`, copy only needed libs). |
| Container runtime | **Podman + CDI** (`nvidia-ctk cdi generate` run by a oneshot service at boot). Docker is the fallback. |
| Init | Trimmed **systemd**. |
| Root FS | **squashfs (zstd), read-only** + overlayfs. Persistent partition for `/var/lib/containers`, logs, results. `nodev,nosuid,noexec` on `/tmp`, `/var/tmp`, `/home`. **No `noexec` on container storage.** |
| Boot | Headless text console on the iGPU; dGPU used for compute only. Secure Boot disabled for demo (documented limitation). Stretch: signed UKI + dm-verity. |

### Security hardening (implement at least these)
1. Read-only root + restrictive mount flags.
2. Kernel lockdown (`integrity`) with module signing (we sign the NVIDIA modules at build time).
3. Sysctl hardening: `kptr_restrict`, `dmesg_restrict`, `unprivileged_bpf_disabled`, Yama `ptrace_scope`.
4. Non-root service user, rootless Podman, `--cap-drop=ALL`, `no-new-privileges`, default seccomp.
5. Minimal attack surface: no SSH by default (or key-only, no root login), default-deny nftables.
6. Stretch: AppArmor profile, dm-verity.

## Repository layout
```
track-c-cuda-distro/
├── README.md
├── CLAUDE.md
├── docs/            # report, architecture, licence inventory, demo script
├── build/
│   ├── Containerfile.builder   # pinned Debian build environment
│   ├── rootfs/                 # debootstrap + package lists (snapshot date pinned)
│   ├── kernel/                 # config fragments, build script, patches
│   ├── nvidia/                 # open-module build, signing, firmware handling
│   ├── container/              # slim CUDA runtime image (multi-stage)
│   └── image/                  # squashfs + GPT/ESP assembly, UKI
├── overlay/         # systemd units, sysctl, nftables, mount units
├── benchmark/       # CUDA sources, runner, telemetry
├── baseline/        # Ubuntu baseline install notes/scripts
├── measure/         # scripts that produce every table in the report
├── test/            # QEMU smoke tests, hardware test checklist
└── LICENSES/        # open source vs proprietary NVIDIA inventory
```

## Phases and verification gates
Do **not** start a phase until the previous gate is passed and the user approves.

| Phase | Work | Gate |
|---|---|---|
| 0. Setup | Podman build env on CachyOS, `f3` check on both USBs, Ubuntu baseline on the 64 GB USB (BitLocker backup deferred to Phase 8) | Baseline boots and runs `nvidia-smi` + a CUDA sample |
| 1. Baseline measurements | Record all metrics for stock | Baseline numbers saved by scripts |
| 2. Minimal bootable rootfs | debootstrap + squashfs + overlayfs, boots in QEMU | Reaches login in QEMU; read-only root confirmed |
| 3. Custom kernel | localmodconfig, trim, boot on real hardware | Boots on Laptop 1 (Laptop 2 in Phase 8); size/boot deltas recorded |
| 4. NVIDIA driver | open modules, signing, GSP firmware | `nvidia-smi` works on Laptop 1 (Laptop 2 in Phase 8) |
| 5. Container stack | Podman, CDI at boot, slim CUDA image | CUDA container runs on Laptop 1 GPU (Laptop 2 in Phase 8) |
| 6. Service + hardening | Auto-start benchmark, hardening, nftables | Benchmark starts at boot as non-root; hardening checks pass |
| 7. Reproducibility | Clean-room rebuild from Git | Rebuild yields a working image (ideally matching hashes) |
| 8. Evaluation | Full measurement runs on both laptops | All tables generated by scripts |
| 9. Report, licences, demo | Report, licence inventory, live + recorded demo | Final review against assignment checklist |

## Measurement rules
- **Image size, report three numbers:** uncompressed rootfs (`du`), compressed squashfs, total used on the medium including the preloaded container image.
- Compare against stock with **identical functionality**. Also run a sensitivity comparison vs. stock Ubuntu with only CUDA *runtime* libs; justify any shortfall below 40%.
- **Boot time:** report firmware, kernel, userspace, and time-to-benchmark separately, from the **same USB medium**. Use `dmesg`, `systemd-analyze`, and a timestamp logged when the benchmark starts.
- **RAM:** `free -m` and `smem` (PSS), idle after 5 min and peak under load. Do not use `toram`.
- **Package count:** `dpkg -l | wc -l` plus a manual inventory of non-dpkg components.
- **GPU benchmark:** memory-bandwidth copy kernel, cuBLAS SGEMM, kernel-launch latency, optionally one cuDNN convolution. Power/thermal via NVML (`nvidia-smi --query-gpu`).
- 5 to 10 runs per measurement, report **median and spread**. AC power only, fixed power profile, log GPU temperature, flag throttled runs.
- Every measurement is produced by a script in `measure/` and saves raw output to `docs/results/`.

## Code and script conventions
- Bash scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, idempotent where possible, a header comment explaining purpose and usage.
- **Pin everything:** apt snapshot date, kernel version, driver version, CUDA/cuDNN versions, container base image digests. Record pins in one place (e.g. `build/versions.env`).
- Set `SOURCE_DATE_EPOCH` for reproducible timestamps.
- Kernel config as fragments, not a single giant `.config`.
- Keep comments explaining *why* a package, module, or option is included or excluded; this feeds the report's justification section.
- Verify version-specific facts (CUDA version, driver branch, kernel LTS, NVIDIA repo support for the chosen Debian release) when pinning. Do not rely on memory.

## Git rules
- **Do NOT append `Co-authored-by: Claude` (or any Claude/Anthropic co-author trailer) to commit messages.** Also do not add "Generated with Claude Code" or similar AI attribution lines to commits or PR descriptions.
- Commits are authored under the user's own git identity; do not change git config.
- **Commit locally after every completed task or phase.**
- **Never push without being explicitly asked.** Commit locally in small, logical steps with clear messages (e.g. `kernel: add localmodconfig fragment for RTX 4050 laptop`).
- Do not commit large binaries, images, kernels, NVIDIA `.run` files, or keys. Use `.gitignore` and document how to fetch or build them.
- Do not force-push or rewrite shared history.

## Licensing and documentation duties
- Maintain `LICENSES/` as we go: for every component record name, version, licence, source URL, and whether it is open or proprietary.
- Proprietary items (NVIDIA userspace libs, GSP firmware, CUDA runtime libs, cuDNN) each need a written justification and a check of the applicable redistribution terms.
- NVIDIA open kernel modules are open source (dual MIT/GPL); the NVIDIA Container Toolkit is Apache-2.0.
- Keep `docs/` updated as decisions are made, including rejected alternatives and why.

## Open questions (do not assume, ask the user)
1. Is Ubuntu Server 24.04 acceptable as the stock baseline, or does the instructor require a specific distro?
2. Podman + CDI or Docker. Is either mandated?
3. Must the benchmark use cuDNN, or are cuBLAS + custom kernels enough? (This sets the size floor.)
4. Is a headless text-console demo acceptable, or is a graphical dashboard expected?
5. Can Secure Boot be disabled on the demo laptop? Is a MUX / dGPU-only mode available in either BIOS?
6. Should the 8 GB drive hold the final image, or does the instructor want an ISO/installer?
7. Is a third (RTX 4070) laptop available as an extra test target?

## Definition of done
Bootable image on the 8 GB USB (also on the 64 GB for measurements), Git repo that rebuilds it from scratch, script-generated comparison tables vs. stock, technical report, licence inventory, and a live + recorded demo of the containerised CUDA benchmark with live metrics.
