const std = @import("std");
const cache_info = @import("cache_info");

const c = @cImport({
    @cInclude("stddef.h");
    @cInclude("matrix.h");
});

extern fn rust_matrix_multiply(
    a_ptr: [*]f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]f32, b_rows: usize, b_cols: usize,
    result_ptr: [*]f32,
    l1_block: usize, l2_block: usize, l3_block: usize
) void;

extern fn zig_matrix_multiply(
    a_ptr: [*]f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]f32, b_rows: usize, b_cols: usize,
    result_ptr: [*]f32,
    l1_block: usize, l2_block: usize, l3_block: usize
) void;

const Impl = enum {
    cpp,
    rust,
    zig,
};

const Benchmark = struct {
    zig_ns: [rounds]u64 = undefined,
    rust_ns: [rounds]u64 = undefined,
    cpp_ns: [rounds]u64 = undefined,
};
//removed the noise and warmup issue on startup now we going for the mean of 5 times run 
const rounds: usize = 5;

fn runOnce(
    impl: Impl,
    a: []f32,
    m: usize,
    n: usize,
    b: []f32,
    p: usize,
    result_zig: []f32,
    result_rust: []f32,
    result_cpp: []f32,
    l1_block: usize, l2_block: usize, l3_block: usize
) !u64 {
    var timer = try std.time.Timer.start();

    switch (impl) {
        .cpp => c.cpp_matrix_multiply(a.ptr, m, n, b.ptr, n, p, result_cpp.ptr, l1_block, l2_block, l3_block),
        .rust => rust_matrix_multiply(a.ptr, m, n, b.ptr, n, p, result_rust.ptr, l1_block, l2_block, l3_block),
        .zig => zig_matrix_multiply(a.ptr, m, n, b.ptr, n, p, result_zig.ptr, l1_block, l2_block, l3_block),
    }

    return timer.read();
}

fn medianNs(values: [rounds]u64) u64 {
    var sorted = values;
    std.sort.heap(u64, &sorted, {}, comptime std.sort.asc(u64));
    return sorted[rounds / 2];
}

fn roundMs(ns: u64) u64 {
    return @divFloor(ns + 500_000, 1_000_000);
}

fn verifyResults(result_zig: []const f32, result_rust: []const f32, result_cpp: []const f32) bool {
    for (0..result_zig.len) |i| {
        if (@abs(result_zig[i] - result_rust[i]) > 0.001 or
            @abs(result_zig[i] - result_cpp[i]) > 0.001)
        {
            return false;
        }
    }
    return true;
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Detect CPU cache layout on the host device(windows/linux/macos) and suggest block sizes
    const cache_layout = try cache_info.detect(allocator);

    std.debug.print("{any}\n", .{cache_layout});
    std.debug.print("Hierarchical Blocks: L1={}, L2={}, L3={}\n", .{
        cache_layout.l1_block,
        cache_layout.l2_block,
        cache_layout.l3_block,
    });

    const m: usize = 1024;
    const n: usize = 1024;
    const p: usize = 1024;

    const a = try allocator.alloc(f32, m * n);
    const b = try allocator.alloc(f32, n * p);
    const result_zig = try allocator.alloc(f32, m * p);
    const result_rust = try allocator.alloc(f32, m * p);
    const result_cpp = try allocator.alloc(f32, m * p);
    defer {
        allocator.free(a);
        allocator.free(b);
        allocator.free(result_zig);
        allocator.free(result_rust);
        allocator.free(result_cpp);
    }
    
    //normal init 
    var prng = std.Random.DefaultPrng.init(0xdeadbeef);
    const rand = prng.random();
    for (a) |*v| v.* = rand.float(f32);
    for (b) |*v| v.* = rand.float(f32);
    
    // setup a warmup order 
    const warmup_order = [_]Impl{ .cpp, .rust, .zig };
    for (warmup_order) |impl| {
        _ = try runOnce(impl, a, m, n, b, p, result_zig, result_rust, result_cpp, cache_layout.l1_block, cache_layout.l2_block, cache_layout.l3_block);
    }
    
    //benchmarking logic, previous version didnt give a fair advantage to a binary run at first now we run all orders first, 
    var benchmark = Benchmark{};
    const order = [_][3]Impl{
        .{ .cpp, .rust, .zig },
        .{ .rust, .zig, .cpp },
        .{ .zig, .cpp, .rust },
    };

    for (0..rounds) |round| {
        for (order[round % order.len]) |impl| {
            const elapsed = try runOnce(impl, a, m, n, b, p, result_zig, result_rust, result_cpp, cache_layout.l1_block, cache_layout.l2_block, cache_layout.l3_block);

            switch (impl) {
                .cpp => benchmark.cpp_ns[round] = elapsed,
                .rust => benchmark.rust_ns[round] = elapsed,
                .zig => benchmark.zig_ns[round] = elapsed,
            }
        }
    }
    
    //mean averaging
    const zig_time = roundMs(medianNs(benchmark.zig_ns));
    const rust_time = roundMs(medianNs(benchmark.rust_ns));
    const cpp_time = roundMs(medianNs(benchmark.cpp_ns));
    const all_match = verifyResults(result_zig, result_rust, result_cpp);

    std.debug.print("\n=== Matrix Multiplication Benchmark ({}x{} * {}x{}) ===\n", .{m, n, n, p});
    std.debug.print("Benchmark: median of {} timed runs after warmup\n", .{rounds});
    std.debug.print("Zig:  {} ms\n", .{zig_time});
    std.debug.print("Rust: {} ms\n", .{rust_time});
    std.debug.print("C++:  {} ms\n", .{cpp_time});
    std.debug.print("Results match: {}\n", .{all_match});
}
