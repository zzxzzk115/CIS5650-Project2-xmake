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

            // Add the left subtree's sum to this group's right endpoint.
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

            // Distribute the parent prefix using the saved left subtree sum.
            int right = (k + 1) * stride - 1;
            int left = right - stride / 2;

            int temp = data[left];
            data[left] = data[right];
            data[right] += temp;
        }

        namespace {
            constexpr int threadsPerBlock = 64;

            // N is a positive power of two. The caller owns the device buffer
            // and timer, and must zero any padding before calling this helper.
            void scanDevice(int N, int *dev_data) {
                const int rounds = ilog2(N);
                for (int d = 0; d < rounds; ++d)
                {
                    const int stride = 1 << (d + 1);
                    const int groups = N / stride;
                    const int blocks = (groups + threadsPerBlock - 1) / threadsPerBlock;
                    kernUpSweep<<<blocks, threadsPerBlock>>>(N, stride, dev_data);
                    checkCUDAError("Failed to launch up-sweep kernel");
                }

                // Clearing the root is part of the exclusive scan algorithm.
                cudaMemsetAsync(dev_data + N - 1, 0, sizeof(int));
                checkCUDAError("Failed to clear scan root");

                for (int d = rounds - 1; d >= 0; --d)
                {
                    const int stride = 1 << (d + 1);
                    const int groups = N / stride;
                    const int blocks = (groups + threadsPerBlock - 1) / threadsPerBlock;
                    kernDownSweep<<<blocks, threadsPerBlock>>>(N, stride, dev_data);
                    checkCUDAError("Failed to launch down-sweep kernel");
                }
            }
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

            const int N = 1 << ilog2ceil(n);

            // Pad to a power of two. The tree scan uses one in-place buffer.
            int *dev_data = nullptr;
            cudaMalloc((void**)&dev_data, N * sizeof(int));
            checkCUDAError("Failed to allocate efficient scan buffer");
            cudaMemset(dev_data, 0, N * sizeof(int));
            cudaMemcpy(dev_data, idata, n * sizeof(int), cudaMemcpyHostToDevice);
            checkCUDAError("Failed to initialize efficient scan buffer");

            timer().startGpuTimer();
            scanDevice(N, dev_data);
            timer().endGpuTimer();

            cudaMemcpy(odata, dev_data, n * sizeof(int), cudaMemcpyDeviceToHost);
            checkCUDAError("Failed to copy efficient scan result to host");
            cudaFree(dev_data);
            checkCUDAError("Failed to free efficient scan buffer");
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
            if (n <= 0)
            {
                timer().startGpuTimer();
                timer().endGpuTimer();
                return 0;
            }

            const int N = 1 << ilog2ceil(n);
            const int blocks = (n + threadsPerBlock - 1) / threadsPerBlock;
            int *dev_input = nullptr;
            int *dev_output = nullptr;
            int *dev_bools = nullptr;
            int *dev_indices = nullptr;

            cudaMalloc((void**)&dev_input, n * sizeof(int));
            cudaMalloc((void**)&dev_output, n * sizeof(int));
            cudaMalloc((void**)&dev_bools, n * sizeof(int));
            cudaMalloc((void**)&dev_indices, N * sizeof(int));
            checkCUDAError("Failed to allocate efficient compaction buffers");

            cudaMemcpy(dev_input, idata, n * sizeof(int), cudaMemcpyHostToDevice);
            cudaMemset(dev_indices, 0, N * sizeof(int));
            checkCUDAError("Failed to initialize efficient compaction buffers");

            timer().startGpuTimer();
            Common::kernMapToBoolean<<<blocks, threadsPerBlock>>>(n, dev_bools, dev_input);
            checkCUDAError("Failed to launch compaction map kernel");

            // Preserve the flags for scatter while scanning a separate copy.
            cudaMemcpyAsync(dev_indices, dev_bools, n * sizeof(int), cudaMemcpyDeviceToDevice);
            checkCUDAError("Failed to copy compaction flags to scan buffer");
            scanDevice(N, dev_indices);

            Common::kernScatter<<<blocks, threadsPerBlock>>>(
                n, dev_output, dev_input, dev_bools, dev_indices);
            checkCUDAError("Failed to launch compaction scatter kernel");
            timer().endGpuTimer();

            // An exclusive scan omits the last flag from the final prefix.
            int lastIndex = 0;
            int lastBool = 0;
            cudaMemcpy(&lastIndex, dev_indices + n - 1, sizeof(int), cudaMemcpyDeviceToHost);
            cudaMemcpy(&lastBool, dev_bools + n - 1, sizeof(int), cudaMemcpyDeviceToHost);
            checkCUDAError("Failed to copy compaction count to host");
            const int count = lastIndex + lastBool;
            if (count > 0)
            {
                cudaMemcpy(odata, dev_output, count * sizeof(int), cudaMemcpyDeviceToHost);
                checkCUDAError("Failed to copy efficient compaction result to host");
            }

            cudaFree(dev_input);
            cudaFree(dev_output);
            cudaFree(dev_bools);
            cudaFree(dev_indices);
            checkCUDAError("Failed to free efficient compaction buffers");
            return count;
        }
    }
}
