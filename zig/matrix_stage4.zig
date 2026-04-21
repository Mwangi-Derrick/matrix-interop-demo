const std = @import("std");

export fn zig_matrix_multiply(
    a_ptr: [*]const f32,
    a_rows: usize,
    a_cols: usize,
    b_ptr: [*]const f32,
    _b_rows: usize,
    b_cols: usize,
    result_ptr: [*]f32,
    l1_block: usize,
    l2_block: usize,
    l3_block: usize,
) void {
    _ = _b_rows;
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;

    @memset(result_ptr[0 .. m * p], 0);

    // L3 Blocking
    var iii: usize = 0;
    while (iii < m) : (iii += l3_block) {
        const i_l3_end = @min(iii + l3_block, m);
        var kkk: usize = 0;
        while (kkk < n) : (kkk += l3_block) {
            const k_l3_end = @min(kkk + l3_block, n);
            var jjj: usize = 0;
            while (jjj < p) : (jjj += l3_block) {
                const j_l3_end = @min(jjj + l3_block, p);

                // L2 Blocking
                var ii: usize = iii;
                while (ii < i_l3_end) : (ii += l2_block) {
                    const i_l2_end = @min(ii + l2_block, i_l3_end);
                    var kk: usize = kkk;
                    while (kk < k_l3_end) : (kk += l2_block) {
                        const k_l2_end = @min(kk + l2_block, k_l3_end);
                        var jj: usize = jjj;
                        while (jj < j_l3_end) : (jj += l2_block) {
                            const j_l2_end = @min(jj + l2_block, j_l3_end);

                            // L1 Blocking
                            var i: usize = ii;
                            while (i < i_l2_end) : (i += l1_block) {
                                const i_l1_end = @min(i + l1_block, i_l2_end);
                                var k: usize = kk;
                                while (k < k_l2_end) : (k += l1_block) {
                                    const k_l1_end = @min(k + l1_block, k_l2_end);
                                    var j: usize = jj;
                                    while (j < j_l2_end) : (j += l1_block) {
                                        const j_l1_end = @min(j + l1_block, j_l2_end);

                                        // Register Micro-kernel (4x4 tile)
                                        // This processes 4 rows and 4 columns of C simultaneously in registers
                                        var im = i;
                                        while (im + 4 <= i_l1_end) : (im += 4) {
                                            var jm = j;
                                            while (jm + 4 <= j_l1_end) : (jm += 4) {
                                                // Load 4x4 accumulators into registers (as vectors)
                                                var c0 = @as(@Vector(4, f32), result_ptr[im * p + jm ..][0..4].*);
                                                var c1 = @as(@Vector(4, f32), result_ptr[(im + 1) * p + jm ..][0..4].*);
                                                var c2 = @as(@Vector(4, f32), result_ptr[(im + 2) * p + jm ..][0..4].*);
                                                var c3 = @as(@Vector(4, f32), result_ptr[(im + 3) * p + jm ..][0..4].*);

                                                var km = k;
                                                while (km < k_l1_end) : (km += 1) {
                                                    // Load 4 elements of B (one row of the 4x4 B tile)
                                                    const b_vec = @as(@Vector(4, f32), b_ptr[km * p + jm ..][0..4].*);
                                                    
                                                    // Broadcast each A element and perform FMA(fused multiply add)
                                                    c0 += @as(@Vector(4, f32), @splat(a_ptr[im * n + km])) * b_vec;
                                                    c1 += @as(@Vector(4, f32), @splat(a_ptr[(im + 1) * n + km])) * b_vec;
                                                    c2 += @as(@Vector(4, f32), @splat(a_ptr[(im + 2) * n + km])) * b_vec;
                                                    c3 += @as(@Vector(4, f32), @splat(a_ptr[(im + 3) * n + km])) * b_vec;
                                                }

                                                // Store 4x4 accumulators back to memory
                                                result_ptr[im * p + jm ..][0..4].* = c0;
                                                result_ptr[(im + 1) * p + jm ..][0..4].* = c1;
                                                result_ptr[(im + 2) * p + jm ..][0..4].* = c2;
                                                result_ptr[(im + 3) * p + jm ..][0..4].* = c3;
                                            }
                                            // Handle J remainders
                                            while (jm < j_l1_end) : (jm += 1) {
                                                var km = k;
                                                while (km < k_l1_end) : (km += 1) {
                                                    const b_val = b_ptr[km * p + jm];
                                                    result_ptr[im * p + jm] += a_ptr[im * n + km] * b_val;
                                                    result_ptr[(im + 1) * p + jm] += a_ptr[(im + 1) * n + km] * b_val;
                                                    result_ptr[(im + 2) * p + jm] += a_ptr[(im + 2) * n + km] * b_val;
                                                    result_ptr[(im + 3) * p + jm] += a_ptr[(im + 3) * n + km] * b_val;
                                                }
                                            }
                                        }
                                        // Handle I remainders
                                        while (im < i_l1_end) : (im += 1) {
                                            var jm = j;
                                            while (jm < j_l1_end) : (jm += 1) {
                                                var km = k;
                                                while (km < k_l1_end) : (km += 1) {
                                                    result_ptr[im * p + jm] += a_ptr[im * n + km] * b_ptr[km * p + jm];
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
