const std = @import("std");

// Stage 4: Single-level cache blocking.
// Uses l1_block to tile the loop nest into blocks that fit in L1 cache.
// Keeps the working set (A tile + B tile + C tile) in L1 for maximum reuse.
// This helped C++ and Rust on i5-6300U but REGRESSED Zig because LLVM's
// auto-vectorizer couldn't prove the @min() bounded while-loops were safe to vectorize.
// On M3 (large caches), tiling hurt ALL languages — the overhead exceeded the cache benefit.
export fn zig_matrix_multiply(
    a_ptr: [*]const f32,
    a_rows: usize,
    a_cols: usize,
    b_ptr: [*]const f32,
    _b_rows: usize,
    b_cols: usize,
    result_ptr: [*]f32,
    l1_block: usize,
    _l2_block: usize,
    _l3_block: usize,
) void {
    _ = _b_rows;
    _ = _l2_block;
    _ = _l3_block;
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;

    @memset(result_ptr[0 .. m * p], 0);

    var ii: usize = 0;
    while (ii < m) : (ii += l1_block) {
        const i_end = @min(ii + l1_block, m);
        var kk: usize = 0;
        while (kk < n) : (kk += l1_block) {
            const k_end = @min(kk + l1_block, n);
            var jj: usize = 0;
            while (jj < p) : (jj += l1_block) {
                const j_end = @min(jj + l1_block, p);

                var i = ii;
                while (i < i_end) : (i += 1) {
                    var k = kk;
                    while (k < k_end) : (k += 1) {
                        const a_val = a_ptr[i * n + k];
                        var j = jj;
                        while (j < j_end) : (j += 1) {
                            result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
                        }
                    }
                }
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
