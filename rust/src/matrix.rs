// rust/matrix.rs
#[no_mangle]
pub extern "C" fn rust_matrix_multiply(
    a_ptr: *const f32, a_rows: usize, a_cols: usize,
    b_ptr: *const f32, b_rows: usize, b_cols: usize,
    result_ptr: *mut f32,
) {
    let a = unsafe { std::slice::from_raw_parts(a_ptr, a_rows * a_cols) };
    let b = unsafe { std::slice::from_raw_parts(b_ptr, b_rows * b_cols) };
    let result = unsafe { std::slice::from_raw_parts_mut(result_ptr, a_rows * b_cols) };
    
    for i in 0..a_rows {
        for j in 0..b_cols {
            let mut sum = 0.0;
            for k in 0..a_cols {
                sum += a[i * a_cols + k] * b[k * b_cols + j];
            }
            result[i * b_cols + j] = sum;
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_matrix_add(
    a_ptr: *const f32,
    b_ptr: *const f32,
    result_ptr: *mut f32,
    len: usize,
) {
    let a = unsafe { std::slice::from_raw_parts(a_ptr, len) };
    let b = unsafe { std::slice::from_raw_parts(b_ptr, len) };
    let result = unsafe { std::slice::from_raw_parts_mut(result_ptr, len) };
    
    for i in 0..len {
        result[i] = a[i] + b[i];
    }
}