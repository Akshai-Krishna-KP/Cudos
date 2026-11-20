// trackc_bench.cu: the Track C GPU benchmark. One run prints one JSON line.
// The same source is used on the stock baseline (built with the host nvcc) and
// inside the custom image's CUDA container, so the GPU numbers are comparable.
//
//   1. Memory bandwidth: grid-stride float4 copy kernel, 256 MiB buffers.
//      GB/s counts bytes read + written.
//   2. cuBLAS SGEMM: N=4096, C = A*B, reported in TFLOP/s (2*N^3 per GEMM).
//   3. Kernel launch latency: an empty kernel, launch + cudaDeviceSynchronize
//      round trip (median of 5000), plus async launch throughput (us/launch).
//
// Build: nvcc -O2 -arch=sm_89 -o trackc_bench trackc_bench.cu -lcublas
// Usage: trackc_bench [--label NAME]
#include <cublas_v2.h>
#include <cuda_runtime.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#define CK(x) do { cudaError_t e = (x); if (e != cudaSuccess) { \
  fprintf(stderr, "CUDA error %s at %s:%d\n", cudaGetErrorString(e), __FILE__, __LINE__); exit(1); } } while (0)
#define CB(x) do { cublasStatus_t s = (x); if (s != CUBLAS_STATUS_SUCCESS) { \
  fprintf(stderr, "cuBLAS error %d at %s:%d\n", (int)s, __FILE__, __LINE__); exit(1); } } while (0)

__global__ void copy_kernel(const float4* __restrict__ in, float4* __restrict__ out, size_t n) {
  for (size_t i = blockIdx.x * (size_t)blockDim.x + threadIdx.x; i < n; i += (size_t)gridDim.x * blockDim.x)
    out[i] = in[i];
}
__global__ void fill_kernel(float* p, size_t n, float v) {
  for (size_t i = blockIdx.x * (size_t)blockDim.x + threadIdx.x; i < n; i += (size_t)gridDim.x * blockDim.x)
    p[i] = v;
}
__global__ void empty_kernel() {}

static double bandwidth_gbs(int sms) {
  const size_t bytes = 256ull << 20, n4 = bytes / sizeof(float4);
  float4 *a, *b;
  CK(cudaMalloc(&a, bytes)); CK(cudaMalloc(&b, bytes));
  CK(cudaMemset(a, 1, bytes));
  const int threads = 256, blocks = sms * 8, iters = 50;
  copy_kernel<<<blocks, threads>>>(a, b, n4);  // warm-up
  CK(cudaDeviceSynchronize());
  cudaEvent_t t0, t1; CK(cudaEventCreate(&t0)); CK(cudaEventCreate(&t1));
  CK(cudaEventRecord(t0));
  for (int i = 0; i < iters; i++) copy_kernel<<<blocks, threads>>>(a, b, n4);
  CK(cudaEventRecord(t1)); CK(cudaEventSynchronize(t1));
  float ms; CK(cudaEventElapsedTime(&ms, t0, t1));
  CK(cudaFree(a)); CK(cudaFree(b));
  return 2.0 * bytes * iters / (ms / 1e3) / 1e9;
}

static double sgemm_tflops() {
  const int N = 4096, iters = 20;
  const size_t n = (size_t)N * N;
  float *A, *B, *C;
  CK(cudaMalloc(&A, n * 4)); CK(cudaMalloc(&B, n * 4)); CK(cudaMalloc(&C, n * 4));
  fill_kernel<<<256, 256>>>(A, n, 1.0f); fill_kernel<<<256, 256>>>(B, n, 0.5f);
  cublasHandle_t h; CB(cublasCreate(&h));
  const float alpha = 1.0f, beta = 0.0f;
  for (int i = 0; i < 3; i++)  // warm-up
    CB(cublasSgemm(h, CUBLAS_OP_N, CUBLAS_OP_N, N, N, N, &alpha, A, N, B, N, &beta, C, N));
  CK(cudaDeviceSynchronize());
  cudaEvent_t t0, t1; CK(cudaEventCreate(&t0)); CK(cudaEventCreate(&t1));
  CK(cudaEventRecord(t0));
  for (int i = 0; i < iters; i++)
    CB(cublasSgemm(h, CUBLAS_OP_N, CUBLAS_OP_N, N, N, N, &alpha, A, N, B, N, &beta, C, N));
  CK(cudaEventRecord(t1)); CK(cudaEventSynchronize(t1));
  float ms; CK(cudaEventElapsedTime(&ms, t0, t1));
  // Correctness spot check: every C element must equal N * 1.0 * 0.5.
  float c0; CK(cudaMemcpy(&c0, C, 4, cudaMemcpyDeviceToHost));
  if (c0 != N * 0.5f) { fprintf(stderr, "SGEMM check failed: %f\n", c0); exit(1); }
  CB(cublasDestroy(h)); CK(cudaFree(A)); CK(cudaFree(B)); CK(cudaFree(C));
  return 2.0 * N * N * (double)N * iters / (ms / 1e3) / 1e12;
}

static void launch_latency(double* rt_median_us, double* async_us) {
  const int rt = 5000, async_n = 20000;
  for (int i = 0; i < 100; i++) empty_kernel<<<1, 1>>>();
  CK(cudaDeviceSynchronize());
  std::vector<double> v(rt);
  for (int i = 0; i < rt; i++) {
    auto a = std::chrono::steady_clock::now();
    empty_kernel<<<1, 1>>>();
    CK(cudaDeviceSynchronize());
    v[i] = std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - a).count();
  }
  std::nth_element(v.begin(), v.begin() + rt / 2, v.end());
  *rt_median_us = v[rt / 2];
  auto a = std::chrono::steady_clock::now();
  for (int i = 0; i < async_n; i++) empty_kernel<<<1, 1>>>();
  CK(cudaDeviceSynchronize());
  *async_us = std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - a).count() / async_n;
}

int main(int argc, char** argv) {
  const char* label = "run";
  for (int i = 1; i + 1 < argc; i++) if (!strcmp(argv[i], "--label")) label = argv[i + 1];
  cudaDeviceProp p; CK(cudaGetDeviceProperties(&p, 0));
  int drv = 0, rtv = 0; CK(cudaDriverGetVersion(&drv)); CK(cudaRuntimeGetVersion(&rtv));
  double bw = bandwidth_gbs(p.multiProcessorCount);
  double tf = sgemm_tflops();
  double rt_us, as_us; launch_latency(&rt_us, &as_us);
  printf("{\"label\":\"%s\",\"gpu\":\"%s\",\"sm\":\"%d%d\",\"cuda_driver\":%d,\"cuda_runtime\":%d,"
         "\"bandwidth_gbs\":%.2f,\"sgemm_tflops\":%.3f,\"launch_roundtrip_us\":%.2f,\"launch_async_us\":%.3f}\n",
         label, p.name, p.major, p.minor, drv, rtv, bw, tf, rt_us, as_us);
  return 0;
}
