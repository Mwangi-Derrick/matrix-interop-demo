#include <cstring>
#include <algorithm>

// Stage 3: Loop flip (i, k, j) — the hardware sympathy breakthrough.
// Moving j to the innermost loop makes both B and Result accesses sequential.
// On i5-6300U: 10,671ms → 419ms (25× speedup). On M3: 1,263ms → 83ms (15× speedup).
// This stage proves that access pattern dominates everything else.
extern "C" {
    void cpp_matrix_multiply(
        const float* a_ptr, size_t a_rows, size_t a_cols,
        const float* b_ptr, size_t b_rows, size_t b_cols,
        float* result_ptr,
        size_t l1_block, size_t l2_block, size_t l3_block
    ) {
        (void)b_rows; (void)l1_block; (void)l2_block; (void)l3_block;

        std::memset(result_ptr, 0, a_rows * b_cols * sizeof(float));

        for (size_t i = 0; i < a_rows; ++i) {
            for (size_t k = 0; k < a_cols; ++k) {
                float a_val = a_ptr[i * a_cols + k];
                for (size_t j = 0; j < b_cols; ++j) {
                    result_ptr[i * b_cols + j] += a_val * b_ptr[k * b_cols + j];
                }
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
