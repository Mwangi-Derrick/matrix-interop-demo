const std = @import("std");

// Stage 2: Same naive (i, j, k) algorithm as Stage 1.
// The difference is in build flags (build.zig): -march=native, -ffast-math, -funroll-loops
// and Rust: RUSTFLAGS="-C target-cpu=native" and Zig: -Dtarget=native.
// This stage proves that compiler flags alone cannot fix a memory-bound bottleneck.
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
