# Technical documentation: Track C GPU appliance ("lazarus")

OS Lab, Track C (CUDA/GPU). A small, read-only Linux distribution for NVIDIA GPU compute:
it boots from USB, configures the GPU by itself, checks it with a CUDA benchmark, and lets a
user write, compile and run CUDA code and install further NVIDIA libraries on demand.
Measured results: `docs/report.md`; rebuilding: `docs/REPRODUCIBILITY.md`.

## Contents
1. At a glance
2. Hardware and media
3. Boot chain
4. Filesystem layout and persistence
5. GPU stack
6. Services
7. User environment (`lazarus` user, `cuda-dev`, `lazarus` package manager, GPU tools)
8. Security model
9. Build system
10. Image variants and deliverables
11. Testing and verification
12. Results summary
13. Troubleshooting and known limitations
14. Repository map

---

## 1. At a glance

| | |
|---|---|
| Base | Debian 13 "trixie" minbase (snapshot 2026-11-14), systemd |
| Kernel | own build: kernel.org 6.12.118 LTS, trimmed to 369 modules (`6.12.118-trackc`) |
| GPU driver | NVIDIA open kernel modules 620.70.06 (compiled at build time), GSP firmware, CUDA 13.5 driver API |
| Root filesystem | squashfs (zstd), read-only; `/etc` overlay in RAM, `/var` and `/home` overlays on a persistent ext4 partition |
| Containers | rootless Podman + CDI (NVIDIA Container Toolkit 1.20.2) |
| CUDA toolkit | not on the host; in the `cuda-dev` container (CUDA 13.5, nvcc + cuBLAS/cuRAND/cuFFT/NVRTC) |
| Extra libraries | `lazarus` package manager: any package from NVIDIA's CUDA mirror, dependencies resolved |
| Size (release image) | 719 MiB on the medium vs 18.6 GiB for stock Ubuntu with the NVIDIA stack (96% smaller), 170 vs 987 packages |
| User | `lazarus` / password `lazarus` (console); SSH key-only |

## 2. Hardware and media

| | Laptop 1 (build host) | Laptop 2 (target, all measurements) |
|---|---|---|
| CPU | Intel Core i7 HX | AMD Ryzen (Lenovo LOQ 83JC) |
| dGPU | RTX 4050 Laptop (Ada, sm_89) | RTX 4060 Laptop (Ada, sm_89), AD107M `10de:28e0` |
| Display | Intel iGPU | AMD iGPU (the panel is wired to the iGPU; the dGPU does compute only) |
| Wi-Fi | Intel | Realtek RTW8852BE (`rtw89`) |

**64 GB SanDisk stick** (measurement medium; both systems on one stick so boot times compare
fairly):

| Part | Size | Content |
|---|---|---|
| p1 ESP | 1 GiB | GRUB + shim (stock), `EFI/trackc/trackc.efi` (our UKI) |
| p2 `baseline-root` | 35 GiB | stock Ubuntu Server 24.04.5 + NVIDIA driver/CUDA/cuDNN/CTK |
| p3 `trackc-root` | 8 GiB | our squashfs root |
| p4 `trackc-persist` (`TRACKC_PERSIST`) | 13.3 GiB | persistent state of our system |

The stick's GRUB has an entry "Track C GPU appliance" that chainloads the UKI. The default
entry is selected from either OS with `build/image/set-boot.sh` (edits GRUB's environment
block on p2; firmware NVRAM is never written).

## 3. Boot chain

```
UEFI firmware
 └─ (64 GB stick) GRUB ──chainload──> EFI/trackc/trackc.efi      (portable .img / ISO: firmware loads EFI/BOOT/BOOTX64.EFI directly)
     UKI = kernel 6.12.118-trackc + initramfs + command line
       root=PARTLABEL=trackc-root rootfstype=squashfs ro quiet modprobe.blacklist=nouveau systemd.gpt_auto=0
     initramfs (initramfs-tools, MODULES=most + squashfs/overlay/ext4)
       local-top/trackc-live   (ISO only: find the ISO, losetup live/rootfs.squashfs -> /dev/loop0)
       mount squashfs root read-only
       init-bottom/trackc-rootfs: /etc overlay (tmpfs), /var + /home overlays (TRACKC_PERSIST),
                                  stable machine-id on persist; tmpfs fallback if no persist
     systemd (multi-user.target)
       gpu-autoconfig -> nvidia-powerd -> trackc-bench (health check) -> trackc-issue (banner)
       trackc-selftest, nftables, (dev/portable) systemd-networkd, systemd-resolved, Wi-Fi, ssh
     tty1: login prompt with GPU banner (portable/ISO: auto-login as lazarus)
```

Measured on Laptop 2 (median of 5): firmware 15.6 s, loader 3.1 s, kernel 4.0 s, userspace
14.2 s, total 36.9 s; kernel start to benchmark running 19 s.

Kernel command line notes: `systemd.gpt_auto=0` stops systemd from auto-mounting the ESP
(not needed, and it failed); `modprobe.blacklist=nouveau` keeps the in-kernel driver away from
the dGPU; `quiet loglevel=3` keeps the console readable.

## 4. Filesystem layout and persistence

| Path | Backing | Flags / why |
|---|---|---|
| `/` | squashfs on p3 (or `/dev/loop0` on the ISO) | `ro`; immutable system, compressed, verified by the self-test |
| `/etc` | overlay: lower = squashfs, upper = tmpfs | configuration changes vanish at reboot (by design) |
| `/var` | overlay: upper on `TRACKC_PERSIST` | logs, benchmark results, `~/cuda` workspaces (`/var/lib/cuda-work/<user>`) |
| `/home` | overlay: upper on `TRACKC_PERSIST` | `nodev,nosuid,noexec` |
| `/tmp`, `/var/tmp` | tmpfs | `nodev,nosuid,noexec` |
| `/run/trackc/persist` | the persist ext4 itself | rootless container storage (`containers/<user>`) and the toolkit archive (`images/`): overlayfs cannot stack on the `/var` overlay, and container storage must allow exec |

`~/cuda` is a symlink to `/var/lib/cuda-work/<user>` because `/home` is `noexec`: programs
compiled there could not run.

The portable image grows its persist partition to the end of the stick on first boot
(`trackc-grow-persist`: only the boot disk, only if persist is the last partition). The ISO
keeps state in RAM unless a `TRACKC_PERSIST` partition exists.

## 5. GPU stack

* **Kernel modules**: `nvidia-kernel-open-dkms 620.70.06` is compiled with DKMS against our
  kernel during the image build; the five `.ko` files are kept in
  `/lib/modules/<ver>/updates/nvidia/`, then DKMS, compilers and kernel headers are purged.
  The NVIDIA build stamp (`user@host`, date) is pinned for reproducibility. Modules are
  unsigned (Secure Boot off, by decision).
* **Userspace on the host**: `libcuda1`, `libnvidia-ml1` (NVML), `firmware-nvidia-gsp`,
  `nvidia-modprobe`, `nvidia-powerd`, Container Toolkit, and the `nvidia-smi` binary
  (extracted; the full driver package would pull ~20 unneeded libraries). No X/GL/Vulkan.
* **`gpu-autoconfig.service`**: scans `/sys/bus/pci/devices` for vendor `0x10de`, class
  `0x03*`; loads `nvidia` + `nvidia_uvm`; creates device nodes
  (`nvidia-ctk system create-device-nodes`); enables persistence mode; writes the CDI spec to
  `/run/cdi/nvidia.yaml`.
* **Dynamic Boost (`nvidia-powerd`)**: required on laptops. Without it the GPU ran 12% slower
  (200 vs 228 GB/s); proven by an A/B test on stock Ubuntu (`docs/results/phase8/powerd-experiment-baseline.txt`).
* **Display**: `options nvidia-drm modeset=0 fbdev=0`. The laptop panel is driven by the iGPU;
  with modeset on, `nvidia-drm` took over the console framebuffer and the screen went blank.
* **Containers**: Podman uses CDI (`--device nvidia.com/gpu=all`); the NVIDIA CDI hook writes
  `ld.so.cache` inside the container, which is why containers are not `--read-only`.

## 6. Services

| Unit | Variants | Purpose |
|---|---|---|
| `gpu-autoconfig.service` | all | GPU detection, driver load, device nodes, persistence mode, CDI spec |
| `nvidia-powerd.service` | all | NVIDIA Dynamic Boost (laptop power management) |
| `trackc-bench.service` | all | boot health check: one benchmark run as user `bench` in a rootless container; result in `/run/trackc-bench/latest.json`, history in `/var/lib/trackc-bench/bench-results.jsonl`; does not block boot (`Type=exec`) |
| `trackc-issue.service` | all | writes the console banner (`/etc/issue`): GPU, driver, CUDA, Dynamic Boost, benchmark, IP |
| `trackc-selftest.service` | all | checks read-only root, overlays, mount flags, persistence; logs `TRACKC-SELFTEST RESULT PASS` |
| `nftables.service` | all | default-deny firewall |
| `systemd-networkd`, `systemd-resolved` | dev, portable, ISO | DHCP and DNS |
| `trackc-wifi-start`, `trackc-wifi@<if>` | dev (lab hotspots), portable (from `trackc/wifi.txt`) | Wi-Fi on any interface name |
| `ssh.service` | dev (always, key-only); portable (only with `trackc/authorized_keys`) | remote access |
| `trackc-provision.service` | portable | optional Wi-Fi / SSH key from the stick's FAT partition; per-stick SSH host keys on persist |
| `trackc-grow-persist.service` | portable | grow persist to the stick's size on first boot |
| `getty@tty1`, `serial-getty@ttyS0` | portable/ISO auto-login as `lazarus` | console |

## 7. User environment

**User**: `lazarus`, password `lazarus` (chosen for the demo). The password works on the local
console only: SSH accepts keys only (`PasswordAuthentication no`, `AllowUsers lazarus`).
On the dev image `lazarus` has passwordless sudo (lab measurement scripts); on the portable
image and ISO it has no sudo. The health-check user `bench` (UID 900) is a system user with no login.

**GPU tools**

| Command | Function |
|---|---|
| `gpu-status` | GPU, driver, CUDA, persistence, Dynamic Boost, boot benchmark result |
| `gpu-watch` | live NVML metrics every second (Ctrl-C quits) |
| `gpu-bench` | run the benchmark container again (memory bandwidth, cuBLAS SGEMM, launch latency) |

**`cuda-dev`**: CUDA 13.5 development container (nvcc, gcc 13, cuBLAS, cuRAND, cuFFT, NVRTC,
nvJitLink, NVTX) run rootless with the GPU, no network, no capabilities, `no-new-privileges`.
`~/cuda` is mounted at `/work` and keeps its files across reboots.
```
cd ~/cuda && nano hello.cu
cuda-dev nvcc -arch=sm_89 -o hello hello.cu && cuda-dev ./hello
cuda-dev make            # in ~/cuda/examples: matmul (CPU vs CUDA vs cuBLAS), pi (cuRAND), vector_add, nvjpeg_roundtrip
cuda-dev                 # interactive shell with the toolkit
```
The toolkit archive (2 GB) lives on the persist partition and is loaded once (a few minutes
on a USB stick). The container runs as rootless "root", which is the user itself outside, so
files in `~/cuda` stay owned by `lazarus` and no re-owned copy of the image is needed.

**`lazarus` package manager**: adds CUDA libraries to the user's toolkit layer.

| Command | Function |
|---|---|
| `lazarus-list [word]` | every package on NVIDIA's CUDA mirror (latest version, size, description; `*` = installed) |
| `lazarus-list --local` | built-in curated list, pinned to CUDA 13.5: nvjpeg, cupti, sanitizer, gdb, npp, cusolver, cusparse, cusparselt, nccl, cutensor, cudnn |
| `lazarus-list --installed` | NVIDIA packages you added |
| `lazarus-install <pkg|name>...` | install any NVIDIA package (or a curated name); apt resolves dependencies |
| `lazarus-remove <pkg|name>...` | remove |
| `lazarus-reset` | back to the original toolkit (deletes the added layer) |
| `lazarus-update` | refresh the package index (otherwise refreshed once a day) |
| `lazarus-mirror [--test|--auto|set nvidia|ubuntu <url>]` | show, measure (with a real-file check), choose mirrors |

How it works: each operation runs `apt-get` in a throw-away container made from the current
toolkit image (root in a user namespace, host network for the download), then `podman commit`
saves the result as `localhost/trackc-cuda-dev-user:latest`, which `cuda-dev` uses from then
on. Sources: NVIDIA's Ubuntu 24.04 CUDA repository (key pinned by SHA-256 + fingerprint) and
the Ubuntu archive for dependencies (signed by Ubuntu). The package index is kept in
`~/.cache/lazarus` (fast listing: ~2.6 s on Laptop 2), uncompressed, without translations; the
first use does a one-time setup (CA certificates, the toolkit's missing dependencies) and
saves it. Mirrors (`/usr/share/trackc/cuda-dev/mirrors.txt`), all checked 2026-11-21:

| Kind | Mirrors |
|---|---|
| NVIDIA | `developer.download.nvidia.com` (global CDN, default), `developer.download.nvidia.cn` (official China mirror, identical signed index) |
| Ubuntu | `archive.ubuntu.com` (default), `mirror.kakao.com`, `mirror.aarnet.edu.au`, `mirrors.edge.kernel.org`, `in.archive.ubuntu.com`, `mirrors.dotsrc.org`, `ftp.jaist.ac.jp` |

`mirror.cse.iitk.ac.in` was removed: its index answers but package files return 404; the
`--test` check now requests a real package file for that reason.

## 8. Security model

1. **Read-only root + restrictive mounts**: squashfs `ro`; `/tmp`, `/var/tmp`, `/home`
   `nodev,nosuid,noexec`; checked at every boot by `trackc-selftest`.
2. **Unprivileged workloads**: health check as system user `bench`; all containers rootless,
   `--cap-drop=all`, `no-new-privileges`, `--network=none`, default seccomp.
3. **Kernel/sysctl hardening** (`/etc/sysctl.d/90-trackc-hardening.conf`): `kptr_restrict=2`,
   `dmesg_restrict=1`, `unprivileged_bpf_disabled=1`, `bpf_jit_harden=2`, Yama
   `ptrace_scope=2`, `kexec_load_disabled=1`, `sysrq=0`, `perf_event_paranoid=3`, protected
   FIFOs/regular files, no ICMP redirects.
4. **Default-deny nftables**: input policy drop; release: nothing inbound; dev/portable: SSH
   (TCP/22) and DHCP replies only when networking is configured.
5. **Minimal attack surface**: 170 packages (release), no compiler or package-manager metadata
   on the host, no SSH or login users in the release image, SSH key-only elsewhere, no shared
   SSH host keys in the portable image, the host laptop's internal NVMe/SATA disks forced
   read-only by a udev rule.

Decisions and limits: Secure Boot, module/UKI signing and kernel lockdown are not used (team
decision 2026-11-20); dm-verity and AppArmor are future work. The `lazarus` password is
deliberately simple and therefore limited to the local console.

## 9. Build system

All builds run in rootless Podman containers on the build host; inputs are pinned in
`build/versions.env`.

| Stage | Script | What it does |
|---|---|---|
| Keys, kernel source | `build/nvidia/fetch-keyring.sh`, `build/kernel/fetch-source.sh` | downloads verified by SHA-256 / fingerprint |
| Package cache | `baseline/prefetch-debs.sh` | Ubuntu + NVIDIA CUDA debs for the containers (offline builds) |
| Containers | `build/container/build-bench-image.sh`, `build-cudadev-image.sh` | multi-stage health-check image (binary + cuBLAS runtime); CUDA dev toolkit image |
| Kernel | `build/kernel/run.sh [iso]` | Debian 6.12 config → `localmodconfig` (module lists from both laptops, `build/kernel/lsmod-*.txt`) → fragments `trackc.config` (+ `trackc-iso.config`) → `bindeb-pkg` |
| Root filesystem | `build/builder.sh build/rootfs/build-rootfs.sh <variant> <kernel>` | `mmdebstrap --variant=minbase` from the snapshot + NVIDIA repo; `customize.sh`: kernel, DKMS modules + purge, overlay files, users, services, variant extras |
| Image | `build/builder.sh build/image/build-image.sh <variant>` | UKI (`ukify`), squashfs (`mksquashfs -comp zstd -Xcompression-level 19 -reproducible`), ESP/persist/GPT (`mtools`, `mkfs.ext4 -d`, `sgdisk`) |
| ISO | `build/builder.sh build/image/build-iso.sh` | `xorriso` UEFI hybrid ISO (El Torito EFI image + appended GPT ESP) |
| Stick | `build/image/install-to-stick.sh`, `set-boot.sh`, `build/container/install-cudadev.sh` | install next to the baseline over SSH, verified by SHA-256 |

Key design choices and rejected alternatives: Yocto/Buildroot rejected (no practical NVIDIA
x86 + CUDA packaging); Docker rejected (root daemon); full CUDA toolkit on the host rejected
(size; the toolkit lives in a container); Debian's kernel replaced by a trimmed LTS build
(UKI halved, 369 instead of ~4,000 modules).

## 10. Image variants and deliverables

| Variant | Use | Users / network | Size |
|---|---|---|---|
| **release** | graded, measured image | no login users, no network services | 719 MiB (squashfs 697 + UKI 22), 170 packages |
| **dev** | the 64 GB measurement stick on Laptop 2 | `lazarus` (sudo), lab hotspots, SSH key-only, `cuda-dev`, `lazarus` | ~776 MiB, ~208 packages |
| **portable** `.img` | shareable flashable image (`out/portable/trackc-gpu-appliance.img`, 3.6 GB; `.img.zst` 2.7 GB) | auto-login `lazarus` (no sudo), Wi-Fi/SSH only from files on the stick, toolkit preloaded, grows to fill the stick | |
| **ISO** | live medium (`out/iso/trackc-gpu-appliance.iso`, 2.8 GB) | as portable, state in RAM | |

## 11. Testing and verification

| Test | Script | Last result |
|---|---|---|
| Boot + read-only self-test + persistence (QEMU/UEFI) | `test/qemu-smoke.sh` | PASS (dev, portable on an 8 GB virtual stick) |
| ISO as CD-ROM and as USB stick (QEMU/UEFI) | `test/iso-smoke.sh` | PASS both (an emulated-firmware USB stall is retried and reported) |
| Acceptance on Laptop 2 (system, read-only root, GPU, hardening, DNS, cuda-dev, lazarus) | `measure/verify-appliance.sh` | see `docs/results/final/verify-laptop2.txt` |
| Reproducibility | two clean release builds | identical squashfs, UKI, package list (`docs/results/phase7/`) |
| Measurements (5 boots, RAM, 7 GPU runs) | `measure/run-target.sh`, `final-table.py` | `docs/results/phase8/comparison.md` |
| User code on the GPU | `benchmark/examples/*` via `cuda-dev` | `docs/results/cuda-dev/` |

## 12. Results summary (Laptop 2, same stick, `docs/results/phase8/comparison.md`)

| Metric | Stock Ubuntu + NVIDIA stack | Custom | Change |
|---|---|---|---|
| Size on the medium | 18.6 GiB | 719 MiB | 96% smaller |
| Packages | 987 | 170 | 83% fewer |
| Boot total / userspace | 46.2 s / 20.2 s | 36.9 s / 14.2 s | 20% / 30% faster |
| Idle RAM used / process PSS | 1,029 / 134 MiB | 812 / 72 MiB | 21% / 46% less |
| Running services | 23 | 11 | 52% fewer |
| GPU memory bandwidth | 228.4 GB/s | 227.5 GB/s | same |
| cuBLAS SGEMM | 8.42 TFLOP/s | 7.72 TFLOP/s | thermal variance (first, coolest run 8.44) |
| Kernel launch round trip | 4.37 µs | 4.46 µs | same |

User code examples (Laptop 2): matrix multiply 2048² 126× faster than one CPU core with our
CUDA kernel, 971× with cuBLAS; Monte Carlo π 1,275×; nvJPEG 1080p encode 8.4 ms / decode 2.4 ms.

## 13. Troubleshooting and known limitations

| Symptom | Cause / action |
|---|---|
| Benchmark low (~200 GB/s) | laptop on battery, or `nvidia-powerd` not running; plug in the charger |
| `cuda-dev` / `lazarus` slow on first use | the 3.6 GB toolkit is unpacked onto the USB stick once; cheap sticks write small files at ~1 MB/s. Use a fast USB 3 stick or USB SSD |
| `lazarus-install` "apt failed" | no internet or DNS; check `getent hosts developer.download.nvidia.com`; try `lazarus-mirror --auto` |
| Blank screen after boot | fixed: `nvidia-drm modeset=0 fbdev=0` (panel on the iGPU) |
| SSH "Permission denied" | key-only by design: `ssh -i ~/.ssh/trackc_ed25519 lazarus@<ip>`; the IP changes between boots (hotspot DHCP) |
| Laptop 2 not reachable | it only knows the configured hotspots; changes to `/etc` (Wi-Fi) last until reboot; permanent: rebuild with `cache/wifi.env` |
| ISO on real hardware | boots in QEMU as CD and USB; on Laptop 2 the USB stick was not found during early boot (under investigation, use the `.img`) |

Known limitations: Secure Boot off (no signing, by decision); tested on Laptop 2 only
(Laptop 1 by hand, `docs/laptop1-test.md`); kernel packages not yet bit-identical between
kernel rebuilds; containers not `--read-only` (CDI hook); `lazarus` additions are online and
not part of the reproducible image.

## 14. Repository map

```
build/          versions.env (all pins), Containerfile.builder, builder.sh
  kernel/       fetch-source.sh, run.sh, build-kernel.sh, trackc.config, trackc-iso.config, lsmod-*.txt
  rootfs/       build-rootfs.sh, customize.sh, packages.txt, packages-dev.txt
  nvidia/       fetch-keyring.sh
  container/    Containerfile.bench, Containerfile.cudadev, build-*-image.sh, install-cudadev.sh
  image/        build-image.sh, build-iso.sh, install-to-stick.sh, set-boot.sh
overlay/
  rootfs/       files in every variant: units, gpu-autoconfig, trackc-bench-run, gpu-*, sysctl, nftables, initramfs scripts
  rootfs-dev/   dev/portable user tools: cuda-dev, lazarus*, libraries.txt, mirrors.txt, sshd, Wi-Fi
  rootfs-portable/  auto-login, provisioning, grow-persist, wired DHCP
  iso/          ISO-only initramfs script + module list
  esp-portable/ README.txt on the portable stick's FAT partition
benchmark/      src/trackc_bench.cu (health check), examples/ (matmul, pi, vector_add, nvjpeg_roundtrip)
baseline/       stock Ubuntu baseline: autoinstall, NVIDIA stack, remote access, prefetch
measure/        collect.sh, run-target.sh, summarize.py, final-table.py, image-size.sh, verify-appliance.sh
test/           qemu-smoke.sh, iso-smoke.sh
docs/           report.md, TECHNICAL.md, REPRODUCIBILITY.md, demo.md, portable-image.md, iso.md, laptop1-test.md, results/
LICENSES/       inventory.md (open-source and proprietary NVIDIA components)
```
