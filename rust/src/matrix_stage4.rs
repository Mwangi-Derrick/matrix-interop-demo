// Stage 4: Single-level cache blocking with l1_block tile size.
// Tiles the loop nest so the working set fits in L1 cache.
// On i5-6300U: 785ms → 647ms (-17%). Rust's LLVM backend recognized step_by(BLOCK_SIZE)
// range patterns and the bounded inner loops as analyzable, generating efficient vector code.
// On M3: 83ms → 126ms (+52% regression) — M3's large caches already held the working set.

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
    l1_block: usize,
    _l2_block: usize,
    _l3_block: usize,
) {
    std::ptr::write_bytes(result_ptr, 0, a_rows * b_cols);

    let mut ii = 0;
    while ii < a_rows {
        let i_end = min(ii + l1_block, a_rows);
        let mut kk = 0;
        while kk < a_cols {
            let k_end = min(kk + l1_block, a_cols);
            let mut jj = 0;
            while jj < b_cols {
                let j_end = min(jj + l1_block, b_cols);

                for i in ii..i_end {
                    for k in kk..k_end {
                        let a_val = *a_ptr.add(i * a_cols + k);
                        for j in jj..j_end {
                            *result_ptr.add(i * b_cols + j) +=
                                a_val * *b_ptr.add(k * b_cols + j);
                        }
                    }
                }
                jj += l1_block;
            }
            kk += l1_block;
        }
        ii += l1_block;
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
