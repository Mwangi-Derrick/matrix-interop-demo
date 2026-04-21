// cpp/matrix.cpp
#include "matrix.h"
#include <cstring>
#include <algorithm> // for std::min

extern "C" {
    void cpp_matrix_multiply(
        const float* a_ptr, size_t a_rows, size_t a_cols,
        const float* b_ptr, size_t _b_rows, size_t b_cols,
        float* result_ptr,
        size_t block_size
    ) {
        // Zero out the result matrix
        std::memset(result_ptr, 0, a_rows * b_cols * sizeof(float));

        // Stage 4: Cache Blocking (Tiling)
        for (size_t ii = 0; ii < a_rows; ii += block_size) {
            for (size_t kk = 0; kk < a_cols; kk += block_size) {
                for (size_t jj = 0; jj < b_cols; jj += block_size) {
                    
                    size_t i_end = std::min(ii + block_size, a_rows);
                    for (size_t i = ii; i < i_end; ++i) {
                        size_t k_end = std::min(kk + block_size, a_cols);
                        for (size_t k = kk; k < k_end; ++k) {
                            float a_val = a_ptr[i * a_cols + k];
                            size_t j_end = std::min(jj + block_size, b_cols);
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
        const float* a_ptr, const float* b_ptr,
        float* result_ptr, size_t len
    ) {
        for (size_t i = 0; i < len; ++i) {
            result_ptr[i] = a_ptr[i] + b_ptr[i];
        }
    }
}
