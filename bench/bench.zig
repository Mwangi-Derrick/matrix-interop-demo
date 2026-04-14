// benchmarks/bench.zig
const std = @import("std");

// Import all three libraries
const c = @cImport({
    @cInclude("matrix.h");  // C++ wrapper
});

extern fn rust_matrix_multiply(
    a_ptr: [*]f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]f32, b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void;

extern fn zig_matrix_multiply(
    a_ptr: [*]f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]f32, b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void;

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Test matrices: 100x50 * 50x100
    const m: usize = 100;
    const n: usize = 50;
    const p: usize = 100;
    
    var a = try allocator.alloc(f32, m * n);
    var b = try allocator.alloc(f32, n * p);
    var result_zig = try allocator.alloc(f32, m * p);
    var result_rust = try allocator.alloc(f32, m * p);
    var result_cpp = try allocator.alloc(f32, m * p);
    defer {
        allocator.free(a);
        allocator.free(b);
        allocator.free(result_zig);
        allocator.free(result_rust);
        allocator.free(result_cpp);
    }
    
    // Initialize with random values
    var prng = std.Random.DefaultPrng.init(0xdeadbeef);
    const rand = prng.random();
    for (a) |*v| v.* = rand.float(f32);
    for (b) |*v| v.* = rand.float(f32);
    
    // Benchmark Zig
    const zig_start = std.time.milliTimestamp();
    zig_matrix_multiply(a.ptr, m, n, b.ptr, n, p, result_zig.ptr);
    const zig_time = std.time.milliTimestamp() - zig_start;
    
    // Benchmark Rust
    const rust_start = std.time.milliTimestamp();
    rust_matrix_multiply(a.ptr, m, n, b.ptr, n, p, result_rust.ptr);
    const rust_time = std.time.milliTimestamp() - rust_start;
    
    // Benchmark C++
    const cpp_start = std.time.milliTimestamp();
    c.cpp_matrix_multiply(a.ptr, m, n, b.ptr, n, p, result_cpp.ptr);
    const cpp_time = std.time.milliTimestamp() - cpp_start;
    
    // Verify all produce same result
    var all_match = true;
    for (0..m*p) |i| {
        if (@abs(result_zig[i] - result_rust[i]) > 0.001 or
            @abs(result_zig[i] - result_cpp[i]) > 0.001) {
            all_match = false;
            break;
        }
    }
    
    std.debug.print("\n=== Matrix Multiplication Benchmark ({}x{} * {}x{}) ===\n", .{m, n, n, p});
    std.debug.print("Zig:  {} ms\n", .{zig_time});
    std.debug.print("Rust: {} ms\n", .{rust_time});
    std.debug.print("C++:  {} ms\n", .{cpp_time});
    std.debug.print("Results match: {}\n", .{all_match});
}