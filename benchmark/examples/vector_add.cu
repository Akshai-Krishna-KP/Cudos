// vector_add.cu: Phase 0 gate sample. Prints the device, runs a vector add on
// the GPU, checks every element on the CPU, and exits non-zero on failure.
// Build: nvcc -O2 -arch=sm_89 -o vector_add vector_add.cu
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>

#define CHECK(x) do { cudaError_t e = (x); if (e != cudaSuccess) { \
  std::fprintf(stderr, "CUDA error %s at %s:%d\n", cudaGetErrorString(e), __FILE__, __LINE__); \
  return 1; } } while (0)

__global__ void add(const float* a, const float* b, float* c, int n) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) c[i] = a[i] + b[i];
}

int main() {
  int dev = 0, drv = 0, rt = 0;
  cudaDeviceProp p;
  CHECK(cudaGetDevice(&dev));
  CHECK(cudaGetDeviceProperties(&p, dev));
  CHECK(cudaDriverGetVersion(&drv));
  CHECK(cudaRuntimeGetVersion(&rt));
  std::printf("device: %s  sm_%d%d  SMs=%d  mem=%.1f GiB\n", p.name, p.major, p.minor,
              p.multiProcessorCount, p.totalGlobalMem / 1073741824.0);
  std::printf("cuda driver API %d, runtime %d\n", drv, rt);

  const int n = 1 << 24;
  const size_t bytes = n * sizeof(float);
  float *a = (float*)std::malloc(bytes), *b = (float*)std::malloc(bytes), *c = (float*)std::malloc(bytes);
  for (int i = 0; i < n; ++i) { a[i] = i * 0.5f; b[i] = i * 2.0f; }
  float *da, *db, *dc;
  CHECK(cudaMalloc(&da, bytes)); CHECK(cudaMalloc(&db, bytes)); CHECK(cudaMalloc(&dc, bytes));
  CHECK(cudaMemcpy(da, a, bytes, cudaMemcpyHostToDevice));
  CHECK(cudaMemcpy(db, b, bytes, cudaMemcpyHostToDevice));
  add<<<(n + 255) / 256, 256>>>(da, db, dc, n);
  CHECK(cudaGetLastError());
  CHECK(cudaMemcpy(c, dc, bytes, cudaMemcpyDeviceToHost));
  for (int i = 0; i < n; ++i)
    if (c[i] != a[i] + b[i]) { std::printf("FAIL at %d\n", i); return 1; }
  std::printf("vector_add: PASS (%d elements)\n", n);
  return 0;
}
