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
    l1_block: usize,
    l2_block: usize,
    l3_block: usize,
) {
    // Zero out result
    std::ptr::write_bytes(result_ptr, 0, a_rows * b_cols);

    // L3 Blocking
    for iii in (0..a_rows).step_by(l3_block) {
        let i_l3_end = min(iii + l3_block, a_rows);
        for kkk in (0..a_cols).step_by(l3_block) {
            let k_l3_end = min(kkk + l3_block, a_cols);
            for jjj in (0..b_cols).step_by(l3_block) {
                let j_l3_end = min(jjj + l3_block, b_cols);

                // L2 Blocking
                for ii in (iii..i_l3_end).step_by(l2_block) {
                    let i_l2_end = min(ii + l2_block, i_l3_end);
                    for kk in (kkk..k_l3_end).step_by(l2_block) {
                        let k_l2_end = min(kk + l2_block, k_l3_end);
                        for jj in (jjj..j_l3_end).step_by(l2_block) {
                            let j_l2_end = min(jj + l2_block, j_l3_end);

                            // L1 Blocking
                            for i in (ii..i_l2_end).step_by(l1_block) {
                                let i_l1_end = min(i + l1_block, i_l2_end);
                                for k in (kk..k_l2_end).step_by(l1_block) {
                                    let k_l1_end = min(k + l1_block, k_l2_end);
                                    for j in (jj..j_l2_end).step_by(l1_block) {
                                        let j_l1_end = min(j + l1_block, j_l2_end);

                                        // --- Standardized 4x4 Register Micro-kernel ---
                                        let mut im = i;
                                        while im + 4 <= i_l1_end {
                                            let mut jm = j;
                                            while jm + 4 <= j_l1_end {
                                                // Load current 4x4 tile into registers
                                                let mut c00 = *result_ptr.add(im * b_cols + jm);
                                                let mut c01 = *result_ptr.add(im * b_cols + jm + 1);
                                                let mut c02 = *result_ptr.add(im * b_cols + jm + 2);
                                                let mut c03 = *result_ptr.add(im * b_cols + jm + 3);

                                                let mut c10 = *result_ptr.add((im + 1) * b_cols + jm);
                                                let mut c11 = *result_ptr.add((im + 1) * b_cols + jm + 1);
                                                let mut c12 = *result_ptr.add((im + 1) * b_cols + jm + 2);
                                                let mut c13 = *result_ptr.add((im + 1) * b_cols + jm + 3);

                                                let mut c20 = *result_ptr.add((im + 2) * b_cols + jm);
                                                let mut c21 = *result_ptr.add((im + 2) * b_cols + jm + 1);
                                                let mut c22 = *result_ptr.add((im + 2) * b_cols + jm + 2);
                                                let mut c23 = *result_ptr.add((im + 2) * b_cols + jm + 3);

                                                let mut c30 = *result_ptr.add((im + 3) * b_cols + jm);
                                                let mut c31 = *result_ptr.add((im + 3) * b_cols + jm + 1);
                                                let mut c32 = *result_ptr.add((im + 3) * b_cols + jm + 2);
                                                let mut c33 = *result_ptr.add((im + 3) * b_cols + jm + 3);

                                                for km in k..k_l1_end {
                                                    let a0 = *a_ptr.add(im * a_cols + km);
                                                    let a1 = *a_ptr.add((im + 1) * a_cols + km);
                                                    let a2 = *a_ptr.add((im + 2) * a_cols + km);
                                                    let a3 = *a_ptr.add((im + 3) * a_cols + km);

                                                    let b0 = *b_ptr.add(km * b_cols + jm);
                                                    let b1 = *b_ptr.add(km * b_cols + jm + 1);
                                                    let b2 = *b_ptr.add(km * b_cols + jm + 2);
                                                    let b3 = *b_ptr.add(km * b_cols + jm + 3);

                                                    c00 += a0 * b0; c01 += a0 * b1; c02 += a0 * b2; c03 += a0 * b3;
                                                    c10 += a1 * b0; c11 += a1 * b1; c12 += a1 * b2; c13 += a1 * b3;
                                                    c20 += a2 * b0; c21 += a2 * b1; c22 += a2 * b2; c23 += a2 * b3;
                                                    c30 += a3 * b0; c31 += a3 * b1; c32 += a3 * b2; c33 += a3 * b3;
                                                }

                                                // Store back
                                                *result_ptr.add(im * b_cols + jm) = c00;
                                                *result_ptr.add(im * b_cols + jm + 1) = c01;
                                                *result_ptr.add(im * b_cols + jm + 2) = c02;
                                                *result_ptr.add(im * b_cols + jm + 3) = c03;

                                                *result_ptr.add((im + 1) * b_cols + jm) = c10;
                                                *result_ptr.add((im + 1) * b_cols + jm + 1) = c11;
                                                *result_ptr.add((im + 1) * b_cols + jm + 2) = c12;
                                                *result_ptr.add((im + 1) * b_cols + jm + 3) = c13;

                                                *result_ptr.add((im + 2) * b_cols + jm) = c20;
                                                *result_ptr.add((im + 2) * b_cols + jm + 1) = c21;
                                                *result_ptr.add((im + 2) * b_cols + jm + 2) = c22;
                                                *result_ptr.add((im + 2) * b_cols + jm + 3) = c23;

                                                *result_ptr.add((im + 3) * b_cols + jm) = c30;
                                                *result_ptr.add((im + 3) * b_cols + jm + 1) = c31;
                                                *result_ptr.add((im + 3) * b_cols + jm + 2) = c32;
                                                *result_ptr.add((im + 3) * b_cols + jm + 3) = c33;

                                                jm += 4;
                                            }
                                            // J remainder
                                            while jm < j_l1_end {
                                                for km in k..k_l1_end {
                                                    let b_val = *b_ptr.add(km * b_cols + jm);
                                                    *result_ptr.add(im * b_cols + jm) += *a_ptr.add(im * a_cols + km) * b_val;
                                                    *result_ptr.add((im + 1) * b_cols + jm) += *a_ptr.add((im + 1) * a_cols + km) * b_val;
                                                    *result_ptr.add((im + 2) * b_cols + jm) += *a_ptr.add((im + 2) * a_cols + km) * b_val;
                                                    *result_ptr.add((im + 3) * b_cols + jm) += *a_ptr.add((im + 3) * a_cols + km) * b_val;
                                                }
                                                jm += 1;
                                            }
                                            im += 4;
                                        }
                                        // I remainder
                                        while im < i_l1_end {
                                            for j_rem in j..j_l1_end {
                                                for km in k..k_l1_end {
                                                    *result_ptr.add(im * b_cols + j_rem) += *a_ptr.add(im * a_cols + km) * *b_ptr.add(km * b_cols + j_rem);
                                                }
                                            }
                                            im += 1;
                                        }
                                    }
                                }
                            }
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
