const std = @import("std");
const cache_info = @import("cache_info");


export fn zig_matrix_multiply(
    a_ptr: [*]const f32,
    a_rows: usize,
    a_cols: usize,
    b_ptr: [*]const f32,
    _b_rows: usize,
    b_cols: usize,
    result_ptr: [*]f32,
    block_size: usize,
) void {
    _ = _b_rows;
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;

    // Use suggested block size if none provided (requires detection/allocator elsewhere,
    // but here we just ensure we have a valid block size)
    const actual_block_size = if (block_size == 0) 64 else block_size;

    @memset(result_ptr[0 .. m * p], 0);

    if (m % actual_block_size == 0 and n % actual_block_size == 0 and p % actual_block_size == 0) {
        var ii: usize = 0;
        while (ii < m) : (ii += actual_block_size) {
            var kk: usize = 0;
            while (kk < n) : (kk += actual_block_size) {
                var jj: usize = 0;
                while (jj < p) : (jj += actual_block_size) {
                    var i: usize = 0;
                    while (i < actual_block_size) : (i += 1) {
                        const a_row = a_ptr + (ii + i) * n + kk;
                        const result_tile = result_ptr + (ii + i) * p + jj;

                        var k: usize = 0;
                        while (k < actual_block_size) : (k += 1) {
                            const a_val = a_row[k];
                            const b_tile = b_ptr + (kk + k) * p + jj;

                            for (0..actual_block_size) |j| {
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
    while (ii < m) : (ii += actual_block_size) {
        const i_end = @min(ii + actual_block_size, m);
        var kk: usize = 0;
        while (kk < n) : (kk += actual_block_size) {
            const k_end = @min(kk + actual_block_size, n);
            var jj: usize = 0;
            while (jj < p) : (jj += actual_block_size) {
                const tile_width = @min(jj + actual_block_size, p) - jj;

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
