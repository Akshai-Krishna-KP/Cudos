# Measurements: custom-dev-laptop2-no-powerd

OS: Debian GNU/Linux 13 (trixie)

## Size and packages

| Metric | Value |
|---|---|
| Root filesystem used (du -sxb /) | 1.38 GiB |
| dpkg packages (ii+hi) | 196 |
| dpkg group `containers` | 0.15 GiB |
| dpkg group `kernel+firmware` | 0.10 GiB |
| dpkg group `lab-remote-access` | 0.01 GiB |
| dpkg group `nvidia-driver+ctk` | 0.20 GiB |
| dpkg group `other` | 0.52 GiB |

## Boot time (5 boots, systemd-analyze)

| Phase | Median (s) | Range (s) |
|---|---|---|
| firmware | 15.59 | 15.57 to 15.61 |
| loader | 4.81 | 4.80 to 4.82 |
| kernel | 3.71 | 3.63 to 4.25 |
| userspace | 14.19 | 13.77 to 14.39 |
| total | 38.48 | 37.86 to 38.83 |
| time_to_benchmark | 20.00 | 19.00 to 22.00 |

## RAM

| Metric | Value |
|---|---|
| Idle used (free -m, after 302 s uptime) | 847 MiB |
| Idle PSS total (all processes) | 57 MiB |
| Running services | 13 |
| Peak used during GPU benchmark | 1225 MiB |

## GPU benchmark (7 runs)

GPU: NVIDIA GeForce RTX 4060 Laptop GPU (sm_89), CUDA driver 13050, runtime 13050

| Metric | Median | Range |
|---|---|---|
| Memory copy bandwidth (GB/s) | 199.79 | 199.62 to 200.04 |
| cuBLAS SGEMM 4096 (TFLOP/s) | 7.522 | 7.389 to 7.737 |
| Launch+sync round trip (us) | 4.53 | 4.51 to 4.57 |
| Async launch (us/launch) | 1.806 | 1.788 to 1.833 |

Max GPU temperature 73.01 C, max power 34.41 W.
Clock event reasons seen (NVML, 0x0=none, 0x1=idle): 0x0000000000000001, 0x0000000000000004, 0x0000000000000024, 0x0000000000000400, 0x0000000000000404, 0x0000000000000424
