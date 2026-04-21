const std = @import("std");

// Stage 1: Naive (i, j, k) loop order — direct textbook formula
// The innermost k-loop strides down columns of B, causing a cache miss on every iteration.
// Result: ~10,000-13,000 ms on i5-6300U, ~1,000 ms on M3.
export fn zig_matrix_multiply(
    a_ptr: [*]const f32,
    a_rows: usize,
    a_cols: usize,
    b_ptr: [*]const f32,
    _b_rows: usize,
    b_cols: usize,
    result_ptr: [*]f32,
    _l1_block: usize,
    _l2_block: usize,
    _l3_block: usize,
) void {
    _ = _b_rows;
    _ = _l1_block;
    _ = _l2_block;
    _ = _l3_block;
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;

    for (0..m) |i| {
        for (0..p) |j| {
            var sum: f32 = 0.0;
            for (0..n) |k| {
                sum += a_ptr[i * n + k] * b_ptr[k * p + j];
            }
            result_ptr[i * p + j] = sum;
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
