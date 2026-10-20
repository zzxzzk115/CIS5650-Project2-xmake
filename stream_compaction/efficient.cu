#include <cuda.h>
#include <cuda_runtime.h>
#include "common.h"
#include "efficient.h"

namespace StreamCompaction {
    namespace Efficient {
        using StreamCompaction::Common::PerformanceTimer;
        PerformanceTimer& timer()
        {
            static PerformanceTimer timer;
            return timer;
        }

        __global__ void kernUpSweep(int N, int stride, int *data) {
            const int k = blockIdx.x * blockDim.x + threadIdx.x;
            if (k >= N / stride)
            {
                return;
            }

            // [x] TODO: Compute this group's left and right node indices.
            // Each group has stride elements; right is its last element.
            // Add the left node's value to the right node in place.
            int right = (k + 1) * stride - 1;
            int left = right - stride / 2;
            data[right] += data[left];
        }

        __global__ void kernDownSweep(int N, int stride, int *data) {
            const int k = blockIdx.x * blockDim.x + threadIdx.x;
            if (k >= N / stride)
            {
                return;
            }

            // [x] TODO: Compute the same left and right indices as up-sweep.
            // Save the old left value, move the right value to the left,
            // then add the saved value to the right.
            int right = (k + 1) * stride - 1;
            int left = right - stride / 2;

            int temp = data[left];
            data[left] = data[right];
            data[right]+= temp;
        }

        /**
         * Performs prefix-sum (aka scan) on idata, storing the result into odata.
         */
        void scan(int n, int *odata, const int *idata) {
            if (n <= 0)
            {
                timer().startGpuTimer();
                timer().endGpuTimer();
                return;
            }

            const int rounds = ilog2ceil(n);
            const int N = 1 << rounds;
            const int threadsPerBlock = 64;

            // Pad to a power of two. The tree scan uses one in-place buffer.
            int *dev_data = nullptr;
            cudaMalloc((void**)&dev_data, N * sizeof(int));
            checkCUDAError("allocate efficient scan buffer");
            cudaMemset(dev_data, 0, N * sizeof(int));
            cudaMemcpy(dev_data, idata, n * sizeof(int), cudaMemcpyHostToDevice);
            checkCUDAError("initialize efficient scan buffer");

            timer().startGpuTimer();
            for (int d = 0; d < rounds; ++d)
            {
                const int stride = 1 << (d + 1);
                const int groups = N / stride;
                const int blocks = (groups + threadsPerBlock - 1) / threadsPerBlock;
                kernUpSweep<<<blocks, threadsPerBlock>>>(N, stride, dev_data);
                checkCUDAError("launch up-sweep");
            }

            // Clear the tree root before down-sweep to get an exclusive scan.
            // This is an algorithm step, so it belongs inside the timer.
            cudaMemsetAsync(dev_data + N - 1, 0, sizeof(int));
            checkCUDAError("clear scan root");

            for (int d = rounds - 1; d >= 0; --d)
            {
                const int stride = 1 << (d + 1);
                const int groups = N / stride;
                const int blocks = (groups + threadsPerBlock - 1) / threadsPerBlock;
                kernDownSweep<<<blocks, threadsPerBlock>>>(N, stride, dev_data);
                checkCUDAError("launch down-sweep");
            }
            timer().endGpuTimer();

            cudaMemcpy(odata, dev_data, n * sizeof(int), cudaMemcpyDeviceToHost);
            checkCUDAError("download efficient scan result");
            cudaFree(dev_data);
            checkCUDAError("free efficient scan buffer");
        }

        /**
         * Performs stream compaction on idata, storing the result into odata.
         * All zeroes are discarded.
         *
         * @param n      The number of elements in idata.
         * @param odata  The array into which to store elements.
         * @param idata  The array of elements to compact.
         * @returns      The number of elements remaining after compaction.
         */
        int compact(int n, int *odata, const int *idata) {
            timer().startGpuTimer();
            // [ ] TODO
            timer().endGpuTimer();
            return -1;
        }
    }
}
