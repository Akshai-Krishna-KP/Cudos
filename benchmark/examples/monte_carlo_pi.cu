// monte_carlo_pi.cu: estimate pi by throwing random points at a square, CPU vs GPU.
// The GPU version uses cuRAND's device API: every thread has its own random stream.
//
//   cuda-dev nvcc -O2 -arch=sm_89 -o pi monte_carlo_pi.cu
//   cuda-dev ./pi 1000000000
#include <cuda_runtime.h>
#include <curand_kernel.h>

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <random>

__global__ void throw_points(unsigned long long per_thread, unsigned long long seed, unsigned long long* hits) {
  unsigned long long id = blockIdx.x * (unsigned long long)blockDim.x + threadIdx.x;
  curandStatePhilox4_32_10_t s;
  curand_init(seed, id, 0, &s);
  unsigned long long in = 0;
  for (unsigned long long i = 0; i < per_thread; i += 2) {
    float4 r = curand_uniform4(&s);  // 4 numbers = 2 points
    in += (r.x * r.x + r.y * r.y <= 1.f) + (r.z * r.z + r.w * r.w <= 1.f);
  }
  atomicAdd(hits, in);
}

int main(int argc, char** argv) {
  unsigned long long n = argc > 1 ? strtoull(argv[1], nullptr, 10) : 1000000000ull;
  printf("Monte Carlo pi with %llu random points\n\n", n);

  // CPU: 1/20 of the points (it is slow), timed and scaled.
  unsigned long long ncpu = n / 20, in = 0;
  std::mt19937_64 g(42); std::uniform_real_distribution<float> u(0.f, 1.f);
  auto t = std::chrono::steady_clock::now();
  for (unsigned long long i = 0; i < ncpu; i++) { float x = u(g), y = u(g); in += x * x + y * y <= 1.f; }
  double cpu_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t).count();
  double cpu_pi = 4.0 * in / ncpu, cpu_full_ms = cpu_ms * 20;

  const int threads = 256, blocks = 24 * 64;
  unsigned long long per = (n + (unsigned long long)threads * blocks - 1) / ((unsigned long long)threads * blocks);
  per += per & 1;
  unsigned long long* d; cudaMalloc(&d, 8); cudaMemset(d, 0, 8);
  throw_points<<<blocks, threads>>>(1000, 1, d); cudaDeviceSynchronize(); cudaMemset(d, 0, 8);  // warm-up
  cudaEvent_t e0, e1; cudaEventCreate(&e0); cudaEventCreate(&e1);
  cudaEventRecord(e0); throw_points<<<blocks, threads>>>(per, 42, d); cudaEventRecord(e1); cudaEventSynchronize(e1);
  float gpu_ms; cudaEventElapsedTime(&gpu_ms, e0, e1);
  unsigned long long hits; cudaMemcpy(&hits, d, 8, cudaMemcpyDeviceToHost);
  cudaError_t err = cudaGetLastError();
  if (err != cudaSuccess) { printf("CUDA error: %s\n", cudaGetErrorString(err)); return 1; }
  double total = (double)per * threads * blocks, gpu_pi = 4.0 * hits / total;

  printf("%-10s pi = %.6f (error %.1e)   %10.1f ms for %llu points (measured on %llu)\n", "CPU", cpu_pi, fabs(cpu_pi - M_PI), cpu_full_ms, n, ncpu);
  printf("%-10s pi = %.6f (error %.1e)   %10.1f ms for %.0f points\n", "GPU", gpu_pi, fabs(gpu_pi - M_PI), gpu_ms, total);
  printf("\nGPU is %.0fx faster (%.1f billion points/s)\n", cpu_full_ms / gpu_ms, total / gpu_ms / 1e6);
  cudaFree(d);
  return 0;
}
