# Measurements: custom-kernel-laptop2

OS: Debian GNU/Linux 13 (trixie)

## Size and packages

| Metric | Value |
|---|---|
| Root filesystem used (du -sxb /) | 1.31 GiB |
| dpkg packages (ii+hi) | 203 |
| dpkg group `containers` | 0.15 GiB |
| dpkg group `kernel+firmware` | 0.03 GiB |
| dpkg group `lab-remote-access` | 0.01 GiB |
| dpkg group `nvidia-driver+ctk` | 0.20 GiB |
| dpkg group `other` | 0.52 GiB |

## Boot time (5 boots, systemd-analyze)

| Phase | Median (s) | Range (s) |
|---|---|---|
| firmware | 15.58 | 15.53 to 15.76 |
| loader | 3.11 | 3.10 to 3.13 |
| kernel | 4.03 | 3.94 to 4.07 |
| userspace | 14.18 | 12.71 to 15.08 |
| total | 36.85 | 35.42 to 37.79 |
| time_to_benchmark | 19.00 | 18.00 to 21.00 |

## RAM

| Metric | Value |
|---|---|
| Idle used (free -m, after 302 s uptime) | 812 MiB |
| Idle PSS total (all processes) | 72 MiB |
| Running services | 11 |
| Peak used during GPU benchmark | 1236 MiB |

## GPU benchmark (7 runs)

GPU: NVIDIA GeForce RTX 4060 Laptop GPU (sm_89), CUDA driver 13050, runtime 13050

| Metric | Median | Range |
|---|---|---|
| Memory copy bandwidth (GB/s) | 227.54 | 227.05 to 227.93 |
| cuBLAS SGEMM 4096 (TFLOP/s) | 7.723 | 7.449 to 8.437 |
| Launch+sync round trip (us) | 4.46 | 4.22 to 4.66 |
| Async launch (us/launch) | 1.799 | 1.779 to 1.824 |

Max GPU temperature 85.06 C, max power 68.95 W.
Clock event reasons seen (NVML, 0x0=none, 0x1=idle): 0x0000000000000001, 0x0000000000000020, 0x0000000000000068, 0x0000000000000400, 0x0000000000000404, 0x0000000000000420, 0x0000000000000448
