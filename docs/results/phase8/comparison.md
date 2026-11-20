## Size

| Metric | Stock Ubuntu + NVIDIA stack | Custom release | Custom dev (lab access) | Reduction (release) |
|---|---|---|---|---|
| Root filesystem, uncompressed (MiB) | 19,098 | 1,192 | 1,344 | 94% less |
| On the medium (MiB) (stock: ext4 used; custom: squashfs + UKI) | 19,098 | 719 | 775 | 96% less |
| Compressed squashfs (MiB) | n/a | 697 | 752 | |
| of which: CUDA benchmark container archive (MiB) | n/a | 466 | 466 | |
| dpkg packages | 987 | 170 | 203 | 83% less |

## Boot time on the same USB stick and laptop (median of 5 boots, seconds)

| Phase | Stock | Custom dev | Reduction |
|---|---|---|---|
| firmware | 15.53 | 15.58 | same (within 1%) |
| loader | 6.70 | 3.11 | 54% less |
| kernel | 3.82 | 4.03 | 6% more |
| userspace | 20.17 | 14.18 | 30% less |
| total | 46.23 | 36.85 | 20% less |
| kernel start to benchmark running | n/a (no auto-start) | 19 | |

## RAM (idle after at least 5 min; peak during the GPU benchmark)

| Metric | Stock | Custom dev | Reduction |
|---|---|---|---|
| Idle used, `free -m` (MiB) | 1029 | 812 | 21% less |
| Idle PSS, all processes (MiB) | 134 | 72 | 46% less |
| Running services | 23 | 11 | 52% less |
| Peak used during benchmark (MiB) | 1452 | 1236 | 15% less |

## GPU benchmark (median of 7 runs; stock = native binary, custom = rootless container)

| Metric | Stock | Custom | Difference |
|---|---|---|---|
| Memory copy bandwidth (GB/s) | 228.39 | 227.54 | -0.4% |
| cuBLAS SGEMM N=4096 (TFLOP/s) | 8.42 | 7.72 | -8.3% |
| Kernel launch + sync (µs) | 4.37 | 4.46 | +2.1% |
| Async launch (µs/launch) | 1.80 | 1.80 | -0.1% |

Max GPU temperature: stock 83.08 °C, custom 85.06 °C.
