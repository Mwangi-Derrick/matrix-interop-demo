export fn zig_matrix_multiply(
    a_ptr: [*]const f32,
    a_rows: usize,
    a_cols: usize,
    b_ptr: [*]const f32,
    _b_rows: usize,
    b_cols: usize,
    result_ptr: [*]f32,
) void {
    _ = _b_rows;
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;

    for (0..m) |i| {
        const a_row = a_ptr + i * n;
        const result_row = result_ptr + i * p;

        for (0..p) |j| {
            var sum: f32 = 0.0;
            var k: usize = 0;
            var b_at = b_ptr + j;
            while (k < n) : (k += 1) {
                sum += a_row[k] * b_at[0];
                b_at += p;
            }
            result_row[j] = sum;
        }
    }
}

export fn zig_matrix_add(
    a_ptr: [*]const f32,
    b_ptr: [*]const f32,
    result_ptr: [*]f32,
    len: usize,
) void {
    for (0..len) |i| {
        result_ptr[i] = a_ptr[i] + b_ptr[i];
    }
}
