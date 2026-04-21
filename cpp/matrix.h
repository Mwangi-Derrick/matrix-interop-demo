#ifndef MATRIX_H
#define MATRIX_H

#include <stddef.h>  // Required for size_t


#ifdef __cplusplus
extern "C" {
#endif

void cpp_matrix_multiply(
    const float* a_ptr, size_t a_rows, size_t a_cols,
    const float* b_ptr, size_t b_rows, size_t b_cols,
    float* result_ptr,
    size_t l1_block, size_t l2_block, size_t l3_block
);

void cpp_matrix_add(
    const float* a_ptr, const float* b_ptr,
    float* result_ptr, size_t len
);

#ifdef __cplusplus
}
#endif

#endif // MATRIX_H