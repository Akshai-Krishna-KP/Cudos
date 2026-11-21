// nvjpeg_roundtrip.cu: needs `cuda-dev install nvjpeg`. Makes a 1920x1080 test image on the
// GPU, JPEG-encodes it ON THE GPU, decodes it back ON THE GPU, and reports size, time and
// image quality (PSNR). Shows an optional library installed with cuda-dev install.
//   cuda-dev nvcc -O2 -arch=sm_89 -o nvjpeg_roundtrip nvjpeg_roundtrip.cu -lnvjpeg
//   cuda-dev ./nvjpeg_roundtrip
#include <cuda_runtime.h>
#include <nvjpeg.h>

#include <cmath>
#include <cstdio>
#include <vector>

#define CK(x) do { auto e = (x); if ((int)e != 0) { printf("error %d at line %d\n", (int)e, __LINE__); return 1; } } while (0)

__global__ void make_image(unsigned char* r, unsigned char* g, unsigned char* b, int w, int h) {
  int x = blockIdx.x * blockDim.x + threadIdx.x, y = blockIdx.y * blockDim.y + threadIdx.y;
  if (x >= w || y >= h) return;
  int i = y * w + x;
  r[i] = (unsigned char)(255.f * x / w);
  g[i] = (unsigned char)(255.f * y / h);
  b[i] = (unsigned char)(127.f + 127.f * sinf(x * 0.02f) * cosf(y * 0.02f));
}

int main() {
  const int W = 1920, H = 1080, N = W * H;
  unsigned char* src; CK(cudaMalloc(&src, 3 * N));
  make_image<<<dim3((W + 15) / 16, (H + 15) / 16), dim3(16, 16)>>>(src, src + N, src + 2 * N, W, H);
  CK(cudaDeviceSynchronize());

  nvjpegHandle_t h; CK(nvjpegCreateSimple(&h));
  nvjpegEncoderState_t es; nvjpegEncoderParams_t ep;
  CK(nvjpegEncoderStateCreate(h, &es, 0)); CK(nvjpegEncoderParamsCreate(h, &ep, 0));
  CK(nvjpegEncoderParamsSetQuality(ep, 90, 0));
  CK(nvjpegEncoderParamsSetSamplingFactors(ep, NVJPEG_CSS_420, 0));
  nvjpegImage_t in{}; for (int c = 0; c < 3; c++) { in.channel[c] = src + c * N; in.pitch[c] = W; }

  cudaEvent_t t0, t1, t2; cudaEventCreate(&t0); cudaEventCreate(&t1); cudaEventCreate(&t2);
  cudaEventRecord(t0);
  CK(nvjpegEncodeImage(h, es, ep, &in, NVJPEG_INPUT_RGB, W, H, 0));
  size_t len = 0; CK(nvjpegEncodeRetrieveBitstream(h, es, nullptr, &len, 0));
  std::vector<unsigned char> jpg(len); CK(nvjpegEncodeRetrieveBitstream(h, es, jpg.data(), &len, 0));
  cudaEventRecord(t1); cudaEventSynchronize(t1);

  unsigned char* dst; CK(cudaMalloc(&dst, 3 * N));
  nvjpegJpegState_t ds; CK(nvjpegJpegStateCreate(h, &ds));
  nvjpegImage_t out{}; for (int c = 0; c < 3; c++) { out.channel[c] = dst + c * N; out.pitch[c] = W; }
  CK(nvjpegDecode(h, ds, jpg.data(), len, NVJPEG_OUTPUT_RGB, &out, 0));
  cudaEventRecord(t2); cudaEventSynchronize(t2);
  float enc_ms, dec_ms; cudaEventElapsedTime(&enc_ms, t0, t1); cudaEventElapsedTime(&dec_ms, t1, t2);

  std::vector<unsigned char> a(3 * N), b(3 * N);
  CK(cudaMemcpy(a.data(), src, 3 * N, cudaMemcpyDeviceToHost)); CK(cudaMemcpy(b.data(), dst, 3 * N, cudaMemcpyDeviceToHost));
  double mse = 0; for (int i = 0; i < 3 * N; i++) { double d = (double)a[i] - b[i]; mse += d * d; } mse /= 3.0 * N;
  double psnr = 10 * log10(255.0 * 255.0 / mse);
  int maj, min_, pat; nvjpegGetProperty(MAJOR_VERSION, &maj); nvjpegGetProperty(MINOR_VERSION, &min_); nvjpegGetProperty(PATCH_LEVEL, &pat);
  cudaDeviceProp p; cudaGetDeviceProperties(&p, 0);
  printf("nvJPEG %d.%d.%d on %s\n", maj, min_, pat, p.name);
  printf("%dx%d RGB (%.1f MB) -> JPEG %.0f KB  (%.0fx smaller)\n", W, H, 3.0 * N / 1e6, len / 1024.0, 3.0 * N / len);
  printf("GPU encode %.2f ms, GPU decode %.2f ms, quality PSNR %.1f dB -> %s\n", enc_ms, dec_ms, psnr, psnr > 30 ? "PASS" : "FAIL");
  return psnr > 30 ? 0 : 1;
}
