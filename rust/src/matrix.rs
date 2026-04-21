// rust/matrix.rs
use std::cmp::min;


#[no_mangle]
pub unsafe extern "C" fn rust_matrix_multiply(
    a_ptr: *const f32,
    a_rows: usize,
    a_cols: usize,
    b_ptr: *const f32,
    _b_rows: usize,
    b_cols: usize,
    result_ptr: *mut f32,
    block_size: usize,
) {
    // Zero out result
    std::ptr::write_bytes(result_ptr, 0, a_rows * b_cols);

    // Stage 4: Cache Blocking (Tiling)
    for ii in (0..a_rows).step_by(block_size) {
        for kk in (0..a_cols).step_by(block_size) {
            for jj in (0..b_cols).step_by(block_size) {
                
                let i_end = min(ii + block_size, a_rows);
                for i in ii..i_end {
                    let k_end = min(kk + block_size, a_cols);
                    for k in kk..k_end {
                        let a_val = *a_ptr.add(i * a_cols + k);
                        let j_end = min(jj + block_size, b_cols);
                        for j in jj..j_end {
                            *result_ptr.add(i * b_cols + j) += a_val * *b_ptr.add(k * b_cols + j);
                        }
                    }
                }
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
