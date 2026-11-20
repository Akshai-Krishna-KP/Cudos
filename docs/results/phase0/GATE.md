# Phase 0 gate: PASSED (2026-11-20)

Stock baseline (Ubuntu Server 24.04.5, 64 GB stick) booted on **Laptop 2**
(Lenovo 83JC, RTX 4060 Laptop, AD107M 10de:28e0, Secure Boot disabled).
Raw output from `baseline/phase0-gate.sh` (run at boot by trackc-phase0-gate.service):
`laptop2/phase0-gate-20261120T060616.txt` (an earlier boot, `...T042006`, is identical).

| Check | Result |
|---|---|
| Kernel | 6.8.0-151-generic, not virtualised |
| NVIDIA module | nvidia-open 620.70.06 (DKMS), in use for 01:00.0 |
| `nvidia-smi` | RTX 4060 Laptop GPU, 8188 MiB, P8, exit 0 |
| CUDA sample `/opt/trackc/vector_add` (sm_89) | PASS, 16,777,216 elements, driver/runtime API 13050 |
| CDI (`nvidia-ctk cdi generate/list`) | 3 devices (gpu=0, gpu=UUID, gpu=all) |

Re-checked live over SSH the same day: nvidia-smi + vector_add PASS.

Notes found during the gate:
- Netplan's networkd backend rejects `match:` for Wi-Fi; the hotspot config had to name
  the interface (`wlo1` on Laptop 2). Fixed generically in the repo afterwards.
- `systemd-analyze` was not finished when the gate ran (boot waits on network-online);
  boot timing is measured properly in Phase 1, not here.
- Laptop 1 was not booted from the stick in Phase 0 (Laptop 2 used via SSH, user-approved plan).
