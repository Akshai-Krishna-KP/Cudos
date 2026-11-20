NVCC ?= nvcc
FLAGS = -O2 -arch=sm_89

all: matmul pi vector_add

matmul: matmul_cpu_vs_gpu.cu
	$(NVCC) $(FLAGS) -o $@ $< -lcublas

pi: monte_carlo_pi.cu
	$(NVCC) $(FLAGS) -o $@ $<

vector_add: vector_add.cu
	$(NVCC) $(FLAGS) -o $@ $<

clean:
	rm -f matmul pi vector_add
