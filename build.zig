// build.zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    
    // Build C++ library
    const cpp_lib = b.addStaticLibrary(.{
        .name = "matrix_cpp",
        .target = target,
        .optimize = optimize,
    });
    cpp_lib.addCSourceFiles(.{
        .files = &.{"cpp/matrix.cpp"},
        .flags = &.{"-std=c++17"},
    });
    cpp_lib.linkLibCpp();
    
    // Build Rust library (requires cargo)
    // For production, you'd use a zig-cmd to run cargo build
    // Here we assume it's pre-built
    
    // Build benchmark executable
    const bench = b.addExecutable(.{
        .name = "bench",
        .target = target,
        .optimize = optimize,
    });
    bench.addCSourceFiles(.{
        .files = &.{"cpp/matrix.cpp"},
        .flags = &.{"-std=c++17"},
    });
    bench.linkLibCpp();
    bench.addIncludePath(.{ .path = "cpp" });
    
    // Add Zig source
    bench.addCSourceFiles(.{
        .files = &.{"zig/matrix.zig"},
        .flags = &.{},
    });
    bench.addCSourceFiles(.{
        .files = &.{"benchmarks/bench.zig"},
        .flags = &.{},
    });
    
    // Link Rust pre-built static lib
    bench.addObjectFile(.{ .path = "rust/target/release/libmatrix_rs.a" });
    
    b.installArtifact(bench);
    
    const run_cmd = b.addRunArtifact(bench);
    run_cmd.step.dependOn(b.getInstallStep());
    
    const run_step = b.step("run", "Run the benchmark");
    run_step.dependOn(&run_cmd.step);
}