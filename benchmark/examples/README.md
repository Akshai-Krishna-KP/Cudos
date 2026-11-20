# CUDA examples for the appliance

Copied to `~/cuda/examples` on first use of `cuda-dev`. The host has no CUDA toolkit;
`cuda-dev` runs the compiler and your program in a rootless container with the GPU.

```sh
cd ~/cuda/examples
cuda-dev make            # builds all examples
cuda-dev ./matmul 2048   # CPU vs hand-written CUDA kernel vs cuBLAS
cuda-dev ./pi            # Monte Carlo pi with cuRAND, CPU vs GPU
cuda-dev ./vector_add    # smallest complete CUDA program
cuda-dev                 # interactive shell with nvcc for your own code
```

Write your own `hello.cu`, then `cuda-dev nvcc -arch=sm_89 -o hello hello.cu && cuda-dev ./hello`.
Files in `~/cuda` survive reboots (persistent partition).
