// cpp/matrix.h
#ifdef __cplusplus
extern "C" {
#endif

void cpp_matrix_multiply(
    const float* a_ptr, size_t a_rows, size_t a_cols,
    const float* b_ptr, size_t b_rows, size_t b_cols,
    float* result_ptr
);

void cpp_matrix_add(
    const float* a_ptr, const float* b_ptr,
    float* result_ptr, size_t len
);

#ifdef __cplusplus
}
#endif