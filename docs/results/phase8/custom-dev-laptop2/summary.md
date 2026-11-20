# Measurements: custom-dev-laptop2

OS: Debian GNU/Linux 13 (trixie)

## Size and packages

| Metric | Value |
|---|---|
| Root filesystem used (du -sxb /) | 1.39 GiB |
| dpkg packages (ii+hi) | 203 |
| dpkg group `containers` | 0.15 GiB |
| dpkg group `kernel+firmware` | 0.10 GiB |
| dpkg group `lab-remote-access` | 0.01 GiB |
| dpkg group `nvidia-driver+ctk` | 0.20 GiB |
| dpkg group `other` | 0.52 GiB |

## Boot time (5 boots, systemd-analyze)

| Phase | Median (s) | Range (s) |
|---|---|---|
| firmware | 15.54 | 15.52 to 16.76 |
| loader | 4.74 | 4.74 to 4.77 |
| kernel | 3.62 | 3.59 to 4.12 |
| userspace | 14.22 | 13.49 to 14.48 |
| total | 38.12 | 37.36 to 39.60 |
| time_to_benchmark | 20.00 | 19.00 to 20.00 |

## RAM

| Metric | Value |
|---|---|
| Idle used (free -m, after 302 s uptime) | 855 MiB |
| Idle PSS total (all processes) | 66 MiB |
| Running services | 12 |
| Peak used during GPU benchmark | 1235 MiB |

## GPU benchmark (7 runs)

GPU: NVIDIA GeForce RTX 4060 Laptop GPU (sm_89), CUDA driver 13050, runtime 13050

| Metric | Median | Range |
|---|---|---|
| Memory copy bandwidth (GB/s) | 228.08 | 227.57 to 228.62 |
| cuBLAS SGEMM 4096 (TFLOP/s) | 8.126 | 7.603 to 8.318 |
| Launch+sync round trip (us) | 4.37 | 4.21 to 4.55 |
| Async launch (us/launch) | 1.798 | 1.789 to 1.819 |

Max GPU temperature 83.62 C, max power 69.83 W.
Clock event reasons seen (NVML, 0x0=none, 0x1=idle): 0x0000000000000001, 0x0000000000000020, 0x0000000000000400, 0x0000000000000404, 0x0000000000000420, 0x0000000000000424, 0x0000000000000448
