const std = @import("std");

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

    @memset(result_ptr[0 .. m * p], 0);

    for (0..m) |i| {
        const a_row = a_ptr + i * n;
        const result_row = result_ptr + i * p;

        for (0..n) |k| {
            const a_val = a_row[k];
            const b_row = b_ptr + k * p;

            for (0..p) |j| {
                result_row[j] += a_val * b_row[j];
            }
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
