#include <cstdio>
#include <vector>
#include "cpu.h"

#include "common.h"

namespace StreamCompaction {
    namespace CPU {
        namespace {
            // Share the scan logic without nesting the CPU performance timer.
            void exclusiveScan(int n, int *odata, const int *idata) {
                int sum = 0;
                for (int i = 0; i < n; ++i)
                {
                    const int value = idata[i];
                    odata[i] = sum;
                    sum += value;
                }
            }
        }

        using StreamCompaction::Common::PerformanceTimer;
        PerformanceTimer& timer()
        {
            static PerformanceTimer timer;
            return timer;
        }

        /**
         * CPU scan (prefix sum).
         * For performance analysis, this is supposed to be a simple for loop.
         * (Optional) For better understanding before starting moving to GPU, you can simulate your GPU scan in this function first.
         */
        void scan(int n, int *odata, const int *idata) {
            timer().startCpuTimer();
            // [x] TODO
            exclusiveScan(n, odata, idata);
            timer().endCpuTimer();
        }

        /**
         * CPU stream compaction without using the scan function.
         *
         * @returns the number of elements remaining after compaction.
         */
        int compactWithoutScan(int n, int *odata, const int *idata) {
            timer().startCpuTimer();
            // [x] TODO
            int c = 0;
            for (int i = 0; i < n; ++i)
            {
                if (idata[i] != 0)
                {
                    odata[c++] = idata[i];
                }
            }
            timer().endCpuTimer();
            return c;
        }

        /**
         * CPU stream compaction using scan and scatter, like the parallel version.
         *
         * @returns the number of elements remaining after compaction.
         */
        int compactWithScan(int n, int *odata, const int *idata) {
            timer().startCpuTimer();
            // [x] TODO
            std::vector<int> bools(n);
            std::vector<int> indices(n);

            // Map every nonzero value to 1, including negative values.
            for (int i = 0; i < n; ++i)
            {
                bools[i] = idata[i] != 0;
            }

            // Keep scatter destinations separate from the output values.
            exclusiveScan(n, indices.data(), bools.data());

            const int count = n > 0 ? indices[n - 1] + bools[n - 1] : 0;
            for (int i = 0; i < n; ++i)
            {
                if (bools[i] != 0)
                {
                    odata[indices[i]] = idata[i];
                }
            }

            timer().endCpuTimer();
            return count;
        }
    }
}
