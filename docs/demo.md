# Live demo script (about 6 minutes)

Setup: Laptop 2 on AC power, the 64 GB stick plugged in, Secure Boot off. The stick boots
the **Track C GPU appliance** by default. Optional: Laptop 1 on the same phone hotspot for SSH.

1. **Cold boot** (about 40 s). Power on Laptop 2: "No setup. On boot it finds the GPU,
   loads the NVIDIA driver, turns on persistence mode and Dynamic Boost, and runs a CUDA
   health check in a locked-down container."
2. **Console banner** (tty1, above the login prompt): GPU name, driver 620.70.06, CUDA 13.5,
   temperature, power, Dynamic Boost, the **boot benchmark result** (about 228 GB/s,
   8 TFLOP/s) and the IP address.
3. **Log in** as `trackc` (console password, or `ssh trackc@<ip>` with the lab key):
   * `gpu-status`: the same report on demand.
   * `gpu-watch`: live metrics every second (Ctrl-C to quit). Leave it running in a second
     terminal (Alt+F2) while step 4 runs, to show the GPU working.
4. **Your own CUDA code** (the real-world part):
   ```
   cd ~/cuda/examples
   cuda-dev make                 # nvcc runs in the CUDA container, not on the host
   cuda-dev ./matmul 2048        # CPU 2.4 s, CUDA kernel 19 ms (126x), cuBLAS 2.5 ms (971x)
   cuda-dev ./pi 1000000000      # 1 billion random points: CPU 13 s, GPU 10 ms
   ```
   Then live-code a tiny kernel:
   ```
   cd ~/cuda && nano hello.cu        # write a __global__ kernel, Ctrl-O to save, Ctrl-X to exit
   cuda-dev nvcc -arch=sm_89 -o hello hello.cu
   cuda-dev ./hello
   ```
   Files in `~/cuda` survive reboots. `cuda-dev` alone opens a shell with `nvcc`.
5. **Locked down while usable:**
   * `findmnt /` shows squashfs `ro`; `sudo touch /usr/x` is refused.
   * `which nvcc gcc` on the host finds nothing; the toolkit lives in a container.
   * `sudo nft list ruleset`: input policy drop, SSH only.
   * `gpu-bench`: re-run the health benchmark as a normal user.
6. **Lean:** `dpkg -l | grep -c ^ii` is about 200 (stock: 987); `uname -r` shows our own
   kernel, `6.12.118-trackc`.

Fallback if something fails live: recorded results in `docs/results/` and the slides.
Back to stock Ubuntu: `build/image/set-boot.sh <ip> once-baseline`, then reboot.
