# Track C: an application-specific Linux distribution for CUDA/GPU compute

OS Lab group assignment, Track C (CUDA/GPU). Repository: this Git repo. Every number in
this report is produced by a script in `measure/`, with raw output under `docs/results/`.

## 1. Goal

A tiny, headless, read-only Linux "GPU appliance" that boots from USB, loads the NVIDIA
driver and automatically starts a containerised CUDA benchmark with live GPU metrics,
and is measurably leaner than a stock distribution with the same functionality.

## 2. Hardware and test setup

| | Laptop 1 (build host) | Laptop 2 (test target) |
|---|---|---|
| CPU | Intel Core i7 HX, 20 threads | AMD Ryzen |
| GPU | RTX 4050 Laptop (Ada, sm_89) | RTX 4060 Laptop (Ada, sm_89), AD107M 10de:28e0 |
| Role | builds everything in rootless Podman containers, drives Laptop 2 over SSH | boots the 64 GB USB stick |

One 64 GB SanDisk USB stick holds **both** systems, so boot times are measured on the same medium:

| Partition | Size | Content |
|---|---|---|
| p1 ESP | 1 GiB | shim + GRUB (baseline), `EFI/trackc/trackc.efi` (custom UKI) |
| p2 | 35 GiB | stock baseline: Ubuntu Server 24.04.5 |
| p3 `trackc-root` | 8 GiB | custom image: squashfs root |
| p4 `trackc-persist` | 13.3 GiB | custom image: persistent state (ext4) |

The boot entry is chosen from the baseline's GRUB environment block (`build/image/set-boot.sh`);
firmware NVRAM is never written, and both systems force the laptop's internal disks read-only.

## 3. Stock baseline (identical functionality)

Ubuntu Server 24.04.5 installed unattended (`baseline/install-baseline-qemu.sh`, autoinstall)
plus NVIDIA's apt repository: `nvidia-open` 620.70.06 (DKMS), full `cuda-toolkit-13-5`,
`cudnn9-cuda-13` 9.28.1, NVIDIA Container Toolkit 1.20.2, Podman. This is how a user would
normally set up a CUDA box.

## 4. Custom image architecture

```
 UEFI -> GRUB (on stick) -> trackc.efi (UKI: Debian kernel 6.12 LTS + initramfs + cmdline)
   initramfs: mount squashfs root (PARTLABEL=trackc-root) read-only
              /etc  = overlay, upper on tmpfs        (config resets every boot)
              /var  = overlay, upper on persist ext4 (logs, results survive)
              /home = overlay, upper on persist, nodev,nosuid,noexec
   systemd:
     gpu-autoconfig.service   sysfs PCI scan -> modprobe nvidia (open modules) ->
                              device nodes -> persistence mode -> CDI spec (/run/cdi)
     trackc-bench.service     user "bench" (non-root) -> rootless Podman ->
                              CUDA container (GPU via CDI) -> results JSONL
     trackc-dashboard.service live nvidia-smi metrics + latest results on tty1
     nftables.service         default-deny firewall
```

| Area | Decision | Why / rejected alternatives |
|---|---|---|
| Build | `mmdebstrap --variant=minbase` against a pinned snapshot.debian.org date, inside a pinned Podman builder container | reproducible, rootless, no host changes; Yocto/Buildroot rejected (no x86 NVIDIA/CUDA packaging) |
| Base | Debian 13 "trixie" | NVIDIA ships a Debian 13 repo with the same driver (620.70.06) and CTK (1.20.2) versions as the baseline |
| Kernel | Debian `linux-image-amd64` 6.12.117 (LTS) | custom-trimmed kernel (Phase 3) deferred, see 9 |
| NVIDIA kernel driver | open GPU kernel modules built with DKMS **at image build time**; then DKMS, compilers and kernel headers are purged from the image | no compiler on the appliance; only 5 `.ko` files ship |
| NVIDIA userspace | only `libcuda1`, `libnvidia-ml1`, GSP firmware, `nvidia-modprobe`, Container Toolkit, plus the `nvidia-smi` binary | the full driver metapackage pulls X/GL/Vulkan/video libraries a headless box never uses |
| CUDA | **not on the host**. The benchmark container (multi-stage) carries only the binary + cuBLAS runtime; cudart linked statically | container built offline from cached debs (`build/container/`) |
| Containers | rootless Podman + CDI | Docker rejected: needs a root daemon |
| Root FS | squashfs (zstd -19, 1 MiB blocks) read-only + overlays | immutable, compressed, tamper-evident |
| Boot | Unified Kernel Image chainloaded from the stick's GRUB | one file to sign later (Secure Boot is off for now) |

### Variants
* **release**: the graded image. No network services, no login users.
* **dev**: release + lab remote access (key-only SSH, hotspot Wi-Fi, NOPASSWD sudo,
  Wi-Fi firmware). Needed only because the target laptop is driven over SSH from
  Laptop 1. Measured separately and accounted for in every comparison.

## 5. Security hardening

1. **Read-only root + restrictive mounts**: squashfs root mounted `ro`; writes refused;
   `/tmp`, `/var/tmp`, `/home` are `nodev,nosuid,noexec` (checked at every boot by
   `trackc-selftest`, results in `docs/results/phase2/`).
2. **Unprivileged workload**: the benchmark runs as system user `bench` in **rootless**
   Podman, with `--cap-drop=all`, `--security-opt=no-new-privileges`, `--network=none`,
   a non-root user (65534) inside the container and the default seccomp profile.
3. **Kernel/sysctl hardening** (`/etc/sysctl.d/90-trackc-hardening.conf`):
   `kptr_restrict=2`, `dmesg_restrict=1`, `unprivileged_bpf_disabled=1`,
   `bpf_jit_harden=2`, Yama `ptrace_scope=2`, `kexec_load_disabled=1`, `sysrq=0`,
   `perf_event_paranoid=3`, protected FIFOs/regular files, no ICMP redirects.
4. **Default-deny nftables firewall**: release image accepts nothing inbound; the dev image
   opens only TCP/22 (+DHCP replies).
5. **Minimal attack surface**: 163 packages (release) vs 987, no compiler, no package
   manager metadata, no SSH in release; internal disks of the host laptop forced read-only by udev.

Not done (documented limitations): kernel lockdown + module signing (the NVIDIA modules are
unsigned, so Secure Boot must be disabled), dm-verity, AppArmor profile.

## 6. Results

(Tables generated by `measure/summarize.py` and `measure/image-size.sh`; see section 6.x.)

## 7. Reproducibility

All pins are in `build/versions.env` (Debian snapshot date, NVIDIA driver/CTK versions,
CUDA version, container base digests, `SOURCE_DATE_EPOCH`). The build runs in a pinned
builder container. Downloaded packages are cached in `cache/` so a rebuild works offline;
apt verifies every package signature either way.

## 8. Licences

See `LICENSES/inventory.md`: open-source components and each proprietary NVIDIA component
(libcuda, NVML, GSP firmware, nvidia-smi, cuBLAS, cudart) with justification.

## 9. Limitations and future work

* Phase 3, the custom-trimmed kernel (localmodconfig from both laptops), was not done in
  the time available; the Debian kernel ships ~400 MB of modules for hardware we do not use.
* NVIDIA modules are unsigned: Secure Boot must be off. Next step: sign modules + UKI with
  our own key (MOK), enable lockdown=integrity, add dm-verity for the squashfs.
* Container rootfs is not `--read-only`: the NVIDIA CDI hook writes `ld.so.cache`.
* Tested on Laptop 2 only; Laptop 1 not booted from the stick.
* First-boot "newest LTS driver" selection and `gpu-driver-update` (design in
  `docs/design/first-boot-gpu-and-dev.md`) not implemented; the driver version is chosen
  and pinned at build time.
