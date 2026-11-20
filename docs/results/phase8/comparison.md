## Size

| Metric | Stock Ubuntu + NVIDIA stack | Custom release | Custom dev (lab access) | Reduction (release) |
|---|---|---|---|---|
| Root filesystem, uncompressed (MiB) | 19,098 | 1,276 | 1,427 | 93% less |
| On the medium (MiB) (stock: ext4 used; custom: squashfs + UKI) | 19,098 | 822 | 877 | 96% less |
| Compressed squashfs (MiB) | n/a | 775 | 831 | |
| of which: CUDA benchmark container archive (MiB) | n/a | 466 | 466 | |
| dpkg packages | 987 | 171 | 203 | 83% less |

## Boot time on the same USB stick and laptop (median of 5 boots, seconds)

| Phase | Stock | Custom dev | Reduction |
|---|---|---|---|
| firmware | 15.53 | 15.54 | same (within 1%) |
| loader | 6.70 | 4.74 | 29% less |
| kernel | 3.82 | 3.62 | 5% less |
| userspace | 20.17 | 14.22 | 30% less |
| total | 46.23 | 38.12 | 18% less |
| kernel start to benchmark running | n/a (no auto-start) | 20 | |

## RAM (idle after at least 5 min; peak during the GPU benchmark)

| Metric | Stock | Custom dev | Reduction |
|---|---|---|---|
| Idle used, `free -m` (MiB) | 1029 | 855 | 17% less |
| Idle PSS, all processes (MiB) | 134 | 66 | 51% less |
| Running services | 23 | 12 | 48% less |
| Peak used during benchmark (MiB) | 1452 | 1235 | 15% less |

## GPU benchmark (median of 7 runs; stock = native binary, custom = rootless container)

| Metric | Stock | Custom | Difference |
|---|---|---|---|
| Memory copy bandwidth (GB/s) | 228.39 | 228.08 | -0.1% |
| cuBLAS SGEMM N=4096 (TFLOP/s) | 8.42 | 8.13 | -3.5% |
| Kernel launch + sync (µs) | 4.37 | 4.37 | +0.0% |
| Async launch (µs/launch) | 1.80 | 1.80 | -0.2% |

Max GPU temperature: stock 83.08 °C, custom 83.62 °C.
