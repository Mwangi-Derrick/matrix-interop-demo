// cpp/matrix.cpp
#include "matrix.h"

class Matrix {
public:
    static void multiply(
        const float* a, size_t a_rows, size_t a_cols,
        const float* b, size_t b_rows, size_t b_cols,
        float* result
    ) {
        for (size_t i = 0; i < a_rows; ++i) {
            for (size_t j = 0; j < b_cols; ++j) {
                float sum = 0.0f;
                for (size_t k = 0; k < a_cols; ++k) {
                    sum += a[i * a_cols + k] * b[k * b_cols + j];
                }
                result[i * b_cols + j] = sum;
            }
        }
    }
    
    static void add(const float* a, const float* b, float* result, size_t len) {
        for (size_t i = 0; i < len; ++i) {
            result[i] = a[i] + b[i];
        }
    }
};

extern "C" {
    void cpp_matrix_multiply(
        const float* a_ptr, size_t a_rows, size_t a_cols,
        const float* b_ptr, size_t b_rows, size_t b_cols,
        float* result_ptr
    ) {
        Matrix::multiply(a_ptr, a_rows, a_cols, b_ptr, b_rows, b_cols, result_ptr);
    }
    
    void cpp_matrix_add(
        const float* a_ptr, const float* b_ptr,
        float* result_ptr, size_t len
    ) {
        Matrix::add(a_ptr, b_ptr, result_ptr, len);
    }
}