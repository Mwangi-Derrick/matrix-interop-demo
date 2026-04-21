const std = @import("std");

// Stage 3: Loop flip (i, k, j) — the hardware sympathy breakthrough.
// Moving j to the innermost loop makes both B and Result accesses sequential.
// The hardware prefetcher runs at full speed. LLVM auto-vectorizes the clean inner loop.
// Result: 12-30× speedup across architectures.
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

    @memset(result_ptr[0 .. m * p], 0);

    for (0..m) |i| {
        for (0..n) |k| {
            const a_val = a_ptr[i * n + k];
            for (0..p) |j| {
                result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
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
