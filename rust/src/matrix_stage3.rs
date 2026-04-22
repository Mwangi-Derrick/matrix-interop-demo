// Stage 3: Loop flip (i, k, j) — the hardware sympathy breakthrough.
// Switched from safe slices to raw pointers (eliminating bounds check overhead).
// Moving j to the innermost loop makes both B and Result accesses sequential.
// On i5-6300U: 12,685ms → 785ms (16× speedup). On M3: 1,084ms → 83ms (13× speedup).


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
    std::ptr::write_bytes(result_ptr, 0, a_rows * b_cols);

    for i in 0..a_rows {
        for k in 0..a_cols {
            let a_val = *a_ptr.add(i * a_cols + k);
            for j in 0..b_cols {
                *result_ptr.add(i * b_cols + j) += a_val * *b_ptr.add(k * b_cols + j);
            }
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
