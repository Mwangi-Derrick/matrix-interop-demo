#include <cstring>
#include <algorithm>

// Stage 4: Single-level cache blocking with l1_block tile size.
// Tiles the loop nest so the working set (A tile + B tile + C tile) fits in L1 cache.
// On i5-6300U: C++ improved 419ms → 401ms (-4%), Rust improved 785ms → 647ms (-17%),
// Zig REGRESSED 865ms → 1,367ms (+58%) due to LLVM auto-vectorization failure.
// On M3: ALL languages regressed because M3's large caches already held the working set.
extern "C" {
    void cpp_matrix_multiply(
        const float* a_ptr, size_t a_rows, size_t a_cols,
        const float* b_ptr, size_t b_rows, size_t b_cols,
        float* result_ptr,
        size_t l1_block, size_t l2_block, size_t l3_block
    ) {
        (void)b_rows; (void)l2_block; (void)l3_block;

        std::memset(result_ptr, 0, a_rows * b_cols * sizeof(float));

        for (size_t ii = 0; ii < a_rows; ii += l1_block) {
            for (size_t kk = 0; kk < a_cols; kk += l1_block) {
                for (size_t jj = 0; jj < b_cols; jj += l1_block) {
                    size_t i_end = std::min(ii + l1_block, a_rows);
                    for (size_t i = ii; i < i_end; ++i) {
                        size_t k_end = std::min(kk + l1_block, a_cols);
                        for (size_t k = kk; k < k_end; ++k) {
                            float a_val = a_ptr[i * a_cols + k];
                            size_t j_end = std::min(jj + l1_block, b_cols);
                            for (size_t j = jj; j < j_end; ++j) {
                                result_ptr[i * b_cols + j] += a_val * b_ptr[k * b_cols + j];
                            }
                        }
                    }
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
