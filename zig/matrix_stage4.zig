const std = @import("std");

pub const BLOCK_SIZE: usize = 64;

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

    if (m % BLOCK_SIZE == 0 and n % BLOCK_SIZE == 0 and p % BLOCK_SIZE == 0) {
        var ii: usize = 0;
        while (ii < m) : (ii += BLOCK_SIZE) {
            var kk: usize = 0;
            while (kk < n) : (kk += BLOCK_SIZE) {
                var jj: usize = 0;
                while (jj < p) : (jj += BLOCK_SIZE) {
                    var i: usize = 0;
                    while (i < BLOCK_SIZE) : (i += 1) {
                        const a_row = a_ptr + (ii + i) * n + kk;
                        const result_tile = result_ptr + (ii + i) * p + jj;

                        var k: usize = 0;
                        while (k < BLOCK_SIZE) : (k += 1) {
                            const a_val = a_row[k];
                            const b_tile = b_ptr + (kk + k) * p + jj;

                            for (0..BLOCK_SIZE) |j| {
                                result_tile[j] += a_val * b_tile[j];
                            }
                        }
                    }
                }
            }
        }
        return;
    }

    var ii: usize = 0;
    while (ii < m) : (ii += BLOCK_SIZE) {
        const i_end = @min(ii + BLOCK_SIZE, m);
        var kk: usize = 0;
        while (kk < n) : (kk += BLOCK_SIZE) {
            const k_end = @min(kk + BLOCK_SIZE, n);
            var jj: usize = 0;
            while (jj < p) : (jj += BLOCK_SIZE) {
                const tile_width = @min(jj + BLOCK_SIZE, p) - jj;

                var i = ii;
                while (i < i_end) : (i += 1) {
                    const a_row = a_ptr + i * n;
                    const result_tile = result_ptr + i * p + jj;

                    var k = kk;
                    while (k < k_end) : (k += 1) {
                        const a_val = a_row[k];
                        const b_tile = b_ptr + k * p + jj;

                        var j: usize = 0;
                        while (j < tile_width) : (j += 1) {
                            result_tile[j] += a_val * b_tile[j];
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
