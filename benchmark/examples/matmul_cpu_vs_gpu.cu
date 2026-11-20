// matmul_cpu_vs_gpu.cu: the same matrix multiplication three ways, timed.
//   1. CPU, one core, cache-friendly loop order (i-k-j)
//   2. GPU, a hand-written tiled CUDA kernel (shared memory)
//   3. GPU, cuBLAS SGEMM (NVIDIA's tuned library)
// Checks that all three agree, prints times and speed-ups.
//
// Build + run on the appliance:
//   cuda-dev nvcc -O2 -arch=sm_89 -o matmul matmul_cpu_vs_gpu.cu -lcublas
//   cuda-dev ./matmul 1024
#include <cublas_v2.h>
#include <cuda_runtime.h>

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <vector>

#define CK(x) do { cudaError_t e = (x); if (e != cudaSuccess) { printf("CUDA error: %s (line %d)\n", cudaGetErrorString(e), __LINE__); return 1; } } while (0)

constexpr int TILE = 32;

__global__ void matmul_tiled(const float* A, const float* B, float* C, int n) {
  __shared__ float As[TILE][TILE], Bs[TILE][TILE];
  int row = blockIdx.y * TILE + threadIdx.y, col = blockIdx.x * TILE + threadIdx.x;
  float acc = 0.f;
  for (int t = 0; t < n; t += TILE) {
    As[threadIdx.y][threadIdx.x] = (row < n && t + threadIdx.x < n) ? A[row * n + t + threadIdx.x] : 0.f;
    Bs[threadIdx.y][threadIdx.x] = (col < n && t + threadIdx.y < n) ? B[(t + threadIdx.y) * n + col] : 0.f;
    __syncthreads();
    for (int k = 0; k < TILE; k++) acc += As[threadIdx.y][k] * Bs[k][threadIdx.x];
    __syncthreads();
  }
  if (row < n && col < n) C[row * n + col] = acc;
}

static double ms_since(std::chrono::steady_clock::time_point t) {
  return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t).count();
}

int main(int argc, char** argv) {
  int n = argc > 1 ? atoi(argv[1]) : 1024;
  size_t sz = (size_t)n * n;
  std::vector<float> A(sz), B(sz), Ccpu(sz, 0.f), Cgpu(sz), Cblas(sz);
  srand(42);
  for (size_t i = 0; i < sz; i++) { A[i] = rand() / (float)RAND_MAX - 0.5f; B[i] = rand() / (float)RAND_MAX - 0.5f; }
  double gflop = 2.0 * n * n * (double)n / 1e9;
  printf("Matrix multiply C = A x B, %d x %d floats (%.1f GFLOP)\n\n", n, n, gflop);

  auto t = std::chrono::steady_clock::now();
  for (int i = 0; i < n; i++)
    for (int k = 0; k < n; k++) { float a = A[(size_t)i * n + k]; for (int j = 0; j < n; j++) Ccpu[(size_t)i * n + j] += a * B[(size_t)k * n + j]; }
  double cpu_ms = ms_since(t);

  float *dA, *dB, *dC;
  CK(cudaMalloc(&dA, sz * 4)); CK(cudaMalloc(&dB, sz * 4)); CK(cudaMalloc(&dC, sz * 4));
  CK(cudaMemcpy(dA, A.data(), sz * 4, cudaMemcpyHostToDevice));
  CK(cudaMemcpy(dB, B.data(), sz * 4, cudaMemcpyHostToDevice));
  dim3 block(TILE, TILE), grid((n + TILE - 1) / TILE, (n + TILE - 1) / TILE);
  matmul_tiled<<<grid, block>>>(dA, dB, dC, n);  // warm-up
  CK(cudaDeviceSynchronize());
  cudaEvent_t e0, e1; cudaEventCreate(&e0); cudaEventCreate(&e1);
  cudaEventRecord(e0); matmul_tiled<<<grid, block>>>(dA, dB, dC, n); cudaEventRecord(e1);
  CK(cudaEventSynchronize(e1)); float kern_ms; cudaEventElapsedTime(&kern_ms, e0, e1);
  CK(cudaMemcpy(Cgpu.data(), dC, sz * 4, cudaMemcpyDeviceToHost));

  cublasHandle_t h; cublasCreate(&h);
  const float one = 1.f, zero = 0.f;
  // cuBLAS is column-major: computing B*A in column-major gives A*B in row-major.
  cublasSgemm(h, CUBLAS_OP_N, CUBLAS_OP_N, n, n, n, &one, dB, n, dA, n, &zero, dC, n);  // warm-up
  CK(cudaDeviceSynchronize());
  cudaEventRecord(e0); cublasSgemm(h, CUBLAS_OP_N, CUBLAS_OP_N, n, n, n, &one, dB, n, dA, n, &zero, dC, n); cudaEventRecord(e1);
  CK(cudaEventSynchronize(e1)); float blas_ms; cudaEventElapsedTime(&blas_ms, e0, e1);
  CK(cudaMemcpy(Cblas.data(), dC, sz * 4, cudaMemcpyDeviceToHost));

  double err1 = 0, err2 = 0;
  for (size_t i = 0; i < sz; i++) { err1 = fmax(err1, fabs(Cgpu[i] - Ccpu[i])); err2 = fmax(err2, fabs(Cblas[i] - Ccpu[i])); }
  printf("%-28s %10.1f ms %9.1f GFLOP/s\n", "CPU (1 core)", cpu_ms, gflop / cpu_ms * 1e3);
  printf("%-28s %10.2f ms %9.1f GFLOP/s   %6.0fx faster\n", "GPU tiled CUDA kernel", kern_ms, gflop / kern_ms * 1e3, cpu_ms / kern_ms);
  printf("%-28s %10.2f ms %9.1f GFLOP/s   %6.0fx faster\n", "GPU cuBLAS SGEMM", blas_ms, gflop / blas_ms * 1e3, cpu_ms / blas_ms);
  printf("\nmax |difference| vs CPU: kernel %.2e, cuBLAS %.2e  -> %s\n", err1, err2, (err1 < 1e-2 && err2 < 1e-2) ? "results agree" : "MISMATCH");
  cublasDestroy(h); cudaFree(dA); cudaFree(dB); cudaFree(dC);
  return 0;
}
