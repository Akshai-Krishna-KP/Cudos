# Live demo script (about 5 minutes)

Setup before the talk: Laptop 2 on AC power, the 64 GB stick plugged in, Secure Boot off.
The stick boots the **Track C GPU appliance** by default (`build/image/set-boot.sh <ip> default-trackc`).
Optional: Laptop 1 on the same hotspot for the SSH part.

1. **Cold boot** (about 40 s). Power on Laptop 2 and say: "No login, no setup. It boots
   straight into the appliance."
2. **Dashboard on screen** (tty1). Point out:
   * GPU name, temperature, power, clocks: live NVML metrics every 2 s.
   * "Benchmark runs" counter: the CUDA container started by itself about 20 s after the
     kernel, as the unprivileged user `bench`, and repeats every 60 s.
   * Each result line: memory bandwidth (GB/s), cuBLAS SGEMM (TFLOP/s), kernel-launch latency (µs).
3. **Read-only root.** From Laptop 1: `ssh trackc@<ip>` (dev image), then:
   * `findmnt /` shows squashfs, `ro`.
   * `sudo touch /usr/x` fails with "Read-only file system".
   * `findmnt /tmp` shows `nodev,nosuid,noexec`.
   * `sudo journalctl -u trackc-selftest -b` shows every check PASS.
4. **Container security.**
   * `ps -o user,cmd -C trackc_bench` (while a run is active): user is not root.
   * `sudo cat /usr/local/sbin/trackc-bench-run`: `--cap-drop=all`, `no-new-privileges`, `--network=none`, rootless Podman.
   * `sudo nft list ruleset`: input policy drop.
5. **Lean.** `dpkg -l | grep -c ^ii` gives about 200 packages (stock: 987).
   `which gcc nvcc` finds nothing: no compiler on the appliance.
6. **Back to stock Ubuntu** (optional): `build/image/set-boot.sh <ip> once-baseline`, then reboot.

If anything fails live, fall back to the recorded measurements in `docs/results/` and the slides.
