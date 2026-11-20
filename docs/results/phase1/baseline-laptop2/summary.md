# Measurements: baseline-laptop2

OS: Ubuntu 24.04.5 LTS

## Size and packages

| Metric | Value |
|---|---|
| Root filesystem used (du -sxb /) | 18.65 GiB |
| dpkg packages (ii+hi) | 987 |
| dpkg group `containers` | 0.12 GiB |
| dpkg group `cuda-toolkit+libs` | 6.76 GiB |
| dpkg group `cudnn` | 2.17 GiB |
| dpkg group `kernel+firmware` | 0.87 GiB |
| dpkg group `lab-remote-access` | 0.01 GiB |
| dpkg group `nvidia-driver+ctk` | 1.15 GiB |
| dpkg group `other` | 1.80 GiB |

## Boot time (5 boots, systemd-analyze)

| Phase | Median (s) | Range (s) |
|---|---|---|
| firmware | 15.53 | 15.51 to 16.67 |
| loader | 6.70 | 6.68 to 6.74 |
| kernel | 3.82 | 3.76 to 3.92 |
| userspace | 20.17 | 19.51 to 22.82 |
| total | 46.23 | 45.66 to 50.00 |

## RAM

| Metric | Value |
|---|---|
| Idle used (free -m, after 488 s uptime) | 1029 MiB |
| Idle PSS total (all processes) | 134 MiB |
| Running services | 23 |
| Peak used during GPU benchmark | 1452 MiB |

## GPU benchmark (7 runs)

GPU: NVIDIA GeForce RTX 4060 Laptop GPU (sm_89), CUDA driver 13050, runtime 13050

| Metric | Median | Range |
|---|---|---|
| Memory copy bandwidth (GB/s) | 228.39 | 222.39 to 228.83 |
| cuBLAS SGEMM 4096 (TFLOP/s) | 8.424 | 7.777 to 8.602 |
| Launch+sync round trip (us) | 4.37 | 4.31 to 4.40 |
| Async launch (us/launch) | 1.801 | 1.795 to 1.824 |

Max GPU temperature 83.08 C, max power 57.88 W.
Clock event reasons seen (NVML, 0x0=none, 0x1=idle): 0x0000000000000001, 0x0000000000000004, 0x0000000000000024, 0x0000000000000400, 0x0000000000000404, 0x0000000000000424
