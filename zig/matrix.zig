// zig/matrix.zig
const std = @import("std");

// Export C ABI for interop
export fn zig_matrix_multiply(
    a_ptr: [*]f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]f32, b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void {
    // Matrix multiplication: A (m x n) * B (n x p) = C (m x p)
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
    a_ptr: [*]f32, b_ptr: [*]f32, 
    result_ptr: [*]f32, len: usize
) void {
    for (0..len) |i| {
        result_ptr[i] = a_ptr[i] + b_ptr[i];
    }
}

// Zig-native version (not exported)
pub fn Matrix(comptime T: type, comptime rows: usize, comptime cols: usize) type {
    return struct {
        data: [rows][cols]T,
        
        fn multiply(self: @This(), other: @This()) [rows][cols]T {
            var result: [rows][cols]T = undefined;
            for (0..rows) |i| {
                for (0..cols) |j| {
                    var sum: T = 0;
                    for (0..cols) |k| {
                        sum += self.data[i][k] * other.data[k][j];
                    }
                    result[i][j] = sum;
                }
            }
            return result;
        }
    };
}