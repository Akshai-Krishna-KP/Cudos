# Laptop 1 hardware check (about 5 minutes, done by hand)

Claude Code runs on Laptop 1, so this test cannot be driven over SSH: you boot the stick on
Laptop 1 yourself and write down what you see.

1. Save your work on Laptop 1, then shut it down.
2. Plug the 64 GB stick into Laptop 1. Power on and press the boot-menu key
   (F12 on most laptops; on this one, the key you use for the CachyOS/Windows menu).
   Choose the USB stick (SanDisk). Secure Boot is already off on Laptop 1.
3. The stick's menu boots **Track C GPU appliance** automatically.
4. Wait about 40 s. Check the console banner above the login prompt:
   - [ ] GPU line shows **RTX 4050 Laptop GPU** and driver 620.70.06
   - [ ] "Boot benchmark:" shows numbers (GB/s, TFLOP/s, µs), possibly after a minute
5. Log in as `trackc` (same password as Laptop 2) and run:
   - [ ] `gpu-status`
   - [ ] `cd ~/cuda/examples && cuda-dev make && cuda-dev ./matmul 2048`
     (needs the CUDA toolkit archive; if it says "not installed", skip this:
     the archive lives on the stick's persist partition and is already there)
   - [ ] `uname -r` shows `6.12.118-trackc`
6. Take a phone photo of the banner and of the matmul output.
7. Power off, remove the stick, and boot Laptop 1 normally. Nothing on its internal disk
   was touched: the appliance forces internal NVMe disks read-only.

Then send me the photos (or type the numbers) and I add them to `docs/results/laptop1/`.
