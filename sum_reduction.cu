
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>

#define BLOCK_SIZE 32 
#define blocks_needed(N) ((N / (2 * BLOCK_SIZE)) + (N % (2 * BLOCK_SIZE) == 0 ? 0 : 1))

// Oh yeah, we're introducing macros now
#define sum_reduce_it(BLK_SIZE, sync_mtd) if (BLOCK_SIZE >= BLK_SIZE) {if(tid < BLK_SIZE/2) sdata[tid] += sdata[tid+BLK_SIZE/2];sync_mtd;}
template <typename T>
__global__ void d_sum_reduce(const T* d_nums, T* d_res, int N) {
    __shared__ T sdata[2 * BLOCK_SIZE];

    unsigned int tid = threadIdx.x;
    unsigned int i = blockIdx.x * 2 * BLOCK_SIZE + tid;
    unsigned int gridSize = BLOCK_SIZE * 2 * gridDim.x;

    sdata[tid] = 0;

    // This layers all would-be blocks into a single block
    while (i < N) {
        sdata[tid] += d_nums[i] + d_nums[i + BLOCK_SIZE];
        i += gridSize;
    }
    __syncthreads();

    sum_reduce_it(512, __syncthreads());
    sum_reduce_it(256, __syncthreads());
    sum_reduce_it(128, __syncthreads());
    if (tid < 32) {
        sum_reduce_it(64, __syncwarp());
        sum_reduce_it(32, __syncwarp());
        sum_reduce_it(16, __syncwarp());
        sum_reduce_it(8, __syncwarp());
        sum_reduce_it(4, __syncwarp());
        sum_reduce_it(2, __syncwarp());
    }

    if (tid == 0)
        d_res[blockIdx.x] = sdata[0];
}

template <typename T>
T sum_reduce(const T* nums, int N) {
    unsigned int num_blocks = blocks_needed(N);
    T* d_nums;
    T* d_res;
    
    cudaMalloc(&d_nums, num_blocks * sizeof(T) * 2 * BLOCK_SIZE);
    cudaMalloc(&d_res, num_blocks * sizeof(T));
    cudaMemcpy(d_nums, nums, sizeof(T) * N, cudaMemcpyHostToDevice);

    // recursive version
    d_sum_reduce<T><<<1, BLOCK_SIZE>>>(d_nums, d_res, N);

    T res; 
    cudaMemcpy(&res, d_res, sizeof(T), cudaMemcpyDeviceToHost);
    
    cudaFree(d_nums);
    cudaFree(d_res);

    return res;
}

/* BEGIN: Stuff that should immediately die once we start actually linking
 * things
 */
template <typename T>
T rand_range(T min, T max) {
    double u = rand() / (double)RAND_MAX;
    return (max - min + 1) * u + min;
}

template <typename T>
T* gen_ints(int N) {
    T* nums = (T*) malloc(sizeof(T) * N);
    srand(time(NULL));
    for (int i = 0; i < N; i++) {
        nums[i] = rand_range<T>(0, 1000);
    }

    return nums;
}
/* END: Stuff that should die */

int main(int argc, char* argv[]) {
    if (argc != 2) {
        printf("Usage: %s N\n", argv[0]);
        exit(-1);
    }

    // Specify the size of the random set of points
    long int N = strtol(argv[1], NULL, 10);
    if (N <= 0) {
        printf("Please enter a positive int for N\n");
        exit(-1);
    }
    else if (N == LONG_MAX || N == LONG_MIN) {
        printf("The provided N is too %s.\n", N == LONG_MAX ? "large" : "small");
        exit(-1);
    }

    printf("N: %d\n", N);

    unsigned long long* nums = gen_ints<unsigned long long>(N);

    unsigned long long* ind = (unsigned long long*) malloc(sizeof(unsigned long long) * N);
    
    unsigned long long sum = 0;
    for (int i = 0; i < N; i++)
        sum += nums[i];
    printf("Serial Sum: %llu\n", sum);

    unsigned long long par_sum = sum_reduce<unsigned long long>(nums, N);
    printf("Parallel Sum: %llu\n", par_sum);

    free(nums);
    return 0;
}