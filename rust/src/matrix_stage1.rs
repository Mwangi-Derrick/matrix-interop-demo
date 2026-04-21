// Stage 1: Naive (i, j, k) loop order — direct textbook formula.
// Uses safe Rust slices with bounds checking.
// The innermost k-loop strides down columns of B, causing a cache miss on every iteration.
// Result: ~12,826 ms on i5-6300U, ~1,081 ms on M3.

#[no_mangle]
pub unsafe extern "C" fn rust_matrix_multiply(
    a_ptr: *const f32,
    a_rows: usize,
    a_cols: usize,
    b_ptr: *const f32,
    _b_rows: usize,
    b_cols: usize,
    result_ptr: *mut f32,
    _l1_block: usize,
    _l2_block: usize,
    _l3_block: usize,
) {
    let a = std::slice::from_raw_parts(a_ptr, a_rows * a_cols);
    let b = std::slice::from_raw_parts(b_ptr, _b_rows * b_cols);
    let result = std::slice::from_raw_parts_mut(result_ptr, a_rows * b_cols);

    for i in 0..a_rows {
        for j in 0..b_cols {
            let mut sum = 0.0f32;
            for k in 0..a_cols {
                sum += a[i * a_cols + k] * b[k * b_cols + j];
            }
            result[i * b_cols + j] = sum;
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn rust_matrix_add(
    a_ptr: *const f32,
    b_ptr: *const f32,
    result_ptr: *mut f32,
    len: usize,
) {
    for i in 0..len {
        *result_ptr.add(i) = *a_ptr.add(i) + *b_ptr.add(i);
    }
}
