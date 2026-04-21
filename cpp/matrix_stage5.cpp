// cpp/matrix.cpp
#include "matrix.h"
#include <cstring>
#include <algorithm>

// Explicit SIMD type, equivalent to Zig's @Vector(4, f32)
typedef float v4f __attribute__((vector_size(16)));

/*
The __restrict keyword in C++ is a non-standard compiler extension that provides a performance hint to the compiler. It is based on the C99 restrict keyword and is supported by major compilers like GCC, MSVC, and Clang. 
Core Functionality
Aliasing Guarantee: Using __restrict on a pointer or reference is a promise from the programmer to the compiler that the memory it points to will only be accessed through that specific pointer (or values derived from it) within its current scope.
Optimization Enablement: Without this keyword, the compiler must assume "aliasing"—the possibility that two pointers might point to the same memory. This forces it to generate conservative, slower machine code (e.g., reloading a value from memory multiple times because a write through a different pointer might have changed it).
Performance Gains: By guaranteeing no aliasing, the compiler can perform aggressive optimizations such as:
Vectorization: Using SIMD instructions to process multiple data elements at once.
Instruction Scheduling: Reordering instructions more freely to avoid pipeline stalls.
Load/Store Elimination: Removing redundant memory reads. 
*/
 

extern "C" {
    void cpp_matrix_multiply(
        const float* __restrict a_ptr, size_t a_rows, size_t a_cols,
        const float* __restrict b_ptr, size_t _b_rows, size_t b_cols,
        float* __restrict result_ptr,
        size_t l1_block, size_t l2_block, size_t l3_block
    ) {
        (void)_b_rows;
        const size_t m = a_rows, n = a_cols, p = b_cols;
        std::memset(result_ptr, 0, m * p * sizeof(float));

        // L3 Blocking (Outer loop)
        for (size_t iii = 0; iii < m; iii += l3_block) {
            const size_t i3e = std::min(iii + l3_block, m);
            for (size_t kkk = 0; kkk < n; kkk += l3_block) {
                const size_t k3e = std::min(kkk + l3_block, n);
                for (size_t jjj = 0; jjj < p; jjj += l3_block) {
                    const size_t j3e = std::min(jjj + l3_block, p);

                    // L2 Blocking (Middle)
                    for (size_t ii = iii; ii < i3e; ii += l2_block) {
                        const size_t i2e = std::min(ii + l2_block, i3e);
                        for (size_t kk = kkk; kk < k3e; kk += l2_block) {
                            const size_t k2e = std::min(kk + l2_block, k3e);
                            for (size_t jj = jjj; jj < j3e; jj += l2_block) {
                                const size_t j2e = std::min(jj + l2_block, j3e);

                                // L1 Blocking (Inner)
                                for (size_t i = ii; i < i2e; i += l1_block) {
                                    const size_t i1e = std::min(i + l1_block, i2e);
                                    for (size_t k = kk; k < k2e; k += l1_block) {
                                        const size_t k1e = std::min(k + l1_block, k2e);
                                        for (size_t j = jj; j < j2e; j += l1_block) {
                                            const size_t j1e = std::min(j + l1_block, j2e);

                                            // --- 4x4 Register Micro-kernel (Explicit SIMD) ---
                                            size_t im = i;
                                            for (; im + 4 <= i1e; im += 4) {
                                                size_t jm = j;
                                                for (; jm + 4 <= j1e; jm += 4) {
                                                    // Load 4x4 C tile into vector registers
                                                    v4f c0, c1, c2, c3;
                                                    memcpy(&c0, result_ptr + im*p + jm, 16);
                                                    memcpy(&c1, result_ptr + (im+1)*p + jm, 16);
                                                    memcpy(&c2, result_ptr + (im+2)*p + jm, 16);
                                                    memcpy(&c3, result_ptr + (im+3)*p + jm, 16);

                                                    for (size_t km = k; km < k1e; ++km) {
                                                        // Load 4 contiguous B elements
                                                        v4f bv;
                                                        memcpy(&bv, b_ptr + km*p + jm, 16);

                                                        // Broadcast A × B row, accumulate into C
                                                        // Clang auto-broadcasts scalar * vector
                                                        c0 += a_ptr[im*n + km]     * bv;
                                                        c1 += a_ptr[(im+1)*n + km] * bv;
                                                        c2 += a_ptr[(im+2)*n + km] * bv;
                                                        c3 += a_ptr[(im+3)*n + km] * bv;
                                                    }

                                                    // Store C tile back
                                                    memcpy(result_ptr + im*p + jm, &c0, 16);
                                                    memcpy(result_ptr + (im+1)*p + jm, &c1, 16);
                                                    memcpy(result_ptr + (im+2)*p + jm, &c2, 16);
                                                    memcpy(result_ptr + (im+3)*p + jm, &c3, 16);
                                                }
                                                // J remainder (scalar)
                                                for (; jm < j1e; ++jm) {
                                                    for (size_t km = k; km < k1e; ++km) {
                                                        float bv = b_ptr[km*p + jm];
                                                        result_ptr[im*p + jm]     += a_ptr[im*n + km] * bv;
                                                        result_ptr[(im+1)*p + jm] += a_ptr[(im+1)*n + km] * bv;
                                                        result_ptr[(im+2)*p + jm] += a_ptr[(im+2)*n + km] * bv;
                                                        result_ptr[(im+3)*p + jm] += a_ptr[(im+3)*n + km] * bv;
                                                    }
                                                }
                                            }
                                            // I remainder (scalar)
                                            for (; im < i1e; ++im) {
                                                for (size_t jm = j; jm < j1e; ++jm) {
                                                    for (size_t km = k; km < k1e; ++km) {
                                                        result_ptr[im*p + jm] += a_ptr[im*n + km] * b_ptr[km*p + jm];
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    void cpp_matrix_add(const float* a_ptr, const float* b_ptr, float* result_ptr, size_t len) {
        for (size_t i = 0; i < len; ++i) result_ptr[i] = a_ptr[i] + b_ptr[i];
    }
}
