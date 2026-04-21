#include <cstring>

// Stage 2: Same naive (i, j, k) algorithm as Stage 1.
// The difference is in build flags: -march=native, -ffast-math, -funroll-loops.
// On i5-6300U, this enabled AVX2 codegen and C++ became fastest (10,671ms vs 12,820ms).
// On M3, near-zero impact — proving you can't SIMD your way out of a cache miss storm.
extern "C" {
    void cpp_matrix_multiply(
        const float* a_ptr, size_t a_rows, size_t a_cols,
        const float* b_ptr, size_t b_rows, size_t b_cols,
        float* result_ptr,
        size_t l1_block, size_t l2_block, size_t l3_block
    ) {
        (void)b_rows; (void)l1_block; (void)l2_block; (void)l3_block;

        for (size_t i = 0; i < a_rows; ++i) {
            for (size_t j = 0; j < b_cols; ++j) {
                float sum = 0.0f;
                for (size_t k = 0; k < a_cols; ++k) {
                    sum += a_ptr[i * a_cols + k] * b_ptr[k * b_cols + j];
                }
                result_ptr[i * b_cols + j] = sum;
            }
        }
    }

    void cpp_matrix_add(
        const float* a_ptr, const float* b_ptr, float* result_ptr, size_t len
    ) {
        for (size_t i = 0; i < len; ++i) {
            result_ptr[i] = a_ptr[i] + b_ptr[i];
        }
    }
}
