#include <cuda.h>
#include <cuda_runtime.h>
#include <utility>
#include "common.h"
#include "naive.h"

namespace StreamCompaction {
    namespace Naive {
        using StreamCompaction::Common::PerformanceTimer;
        PerformanceTimer& timer()
        {
            static PerformanceTimer timer;
            return timer;
        }
        // [x] TODO __global__
        __global__ void kernScan(int n, int offset, int *odata, const int *idata) {
            unsigned int index = blockIdx.x * blockDim.x + threadIdx.x;
            if (index >= n)
            {
                return;
            }

            if (index >= offset)
            {
                // Write this round's accumulated value to odata[index].
                odata[index] = idata[index - offset] + idata[index];
            }
            else
            {
                // Copy this round's unchanged value to odata[index].
                odata[index] = idata[index];
            }
        }

        __global__ void kernShift(int n, int *odata, const int *idata) {
            unsigned int index = blockIdx.x * blockDim.x + threadIdx.x;
            if (index >= n)
            {
                return;
            }

            odata[index] = index == 0 ? 0 : idata[index - 1];
        }

        /**
         * Performs prefix-sum (aka scan) on idata, storing the result into odata.
         */
        void scan(int n, int *odata, const int *idata) {
            // [x] TODO
            // R/W buffers to avoid race condtion.
            int *dev_odata1, *dev_odata2;
            cudaMalloc((void**)&dev_odata1, n * sizeof(int));
            cudaMalloc((void**)&dev_odata2, n * sizeof(int));
            cudaMemcpy(dev_odata1, idata, n * sizeof(int), cudaMemcpyHostToDevice);

            const int threadPerBlock = 64;
            const int blocks = (n + threadPerBlock - 1) / threadPerBlock;
            int *readBuffer = dev_odata1;
            int *writeBuffer = dev_odata2;
            const int rounds = ilog2ceil(n);
            timer().startGpuTimer();
            for (int d = 1; d <= rounds; ++d)
            {
                const int offset = 1 << (d - 1);
                kernScan<<<blocks, threadPerBlock>>>(n, offset, writeBuffer, readBuffer);
                std::swap(readBuffer, writeBuffer);
            }

            // Convert the inclusive result to exclusive scan output.
            kernShift<<<blocks, threadPerBlock>>>(n, writeBuffer, readBuffer);
            std::swap(readBuffer, writeBuffer);
            timer().endGpuTimer();

            cudaMemcpy(odata, readBuffer, n * sizeof(int), cudaMemcpyDeviceToHost);

            cudaFree(dev_odata1);
            cudaFree(dev_odata2);
        }
    }
}
