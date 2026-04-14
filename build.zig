const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build the benchmark executable
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/bench.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link C++ implementation with g++
    bench.addCSourceFiles(.{
        .files = &.{"cpp/matrix.cpp"},
        .flags = &.{"-std=c++17"},
    });
    bench.addIncludePath(b.path("cpp"));
    
    // Link with g++ standard library
    bench.linkSystemLibrary("stdc++");

    // Compile and link Zig implementation
    const zig_obj = b.addObject(.{
        .name = "zig_matrix",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig/matrix.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bench.addObject(zig_obj);

    // Link Rust static library
    const rust_lib_path = switch (target.result.os.tag) {
        .windows => "rust/target/x86_64-pc-windows-gnu/release/libmatrix_rs.a",
        .linux => "rust/target/x86_64-unknown-linux-gnu/release/libmatrix_rs.a",
        .macos => "rust/target/x86_64-apple-darwin/release/libmatrix_rs.a",
        else => @compileError("Unsupported OS"),
    };
    bench.addObjectFile(b.path(rust_lib_path));

    // Windows-specific libraries (only if needed for Rust/C++ interop)
    if (target.result.os.tag == .windows) {
        bench.linkSystemLibrary("user32");
        bench.linkSystemLibrary("kernel32");
        bench.linkSystemLibrary("ws2_32");
        bench.linkSystemLibrary("advapi32");
        bench.linkSystemLibrary("ntdll");
    }

    // Link libc
    bench.linkLibC();

    b.installArtifact(bench);

    const run_cmd = b.addRunArtifact(bench);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the benchmark");
    run_step.dependOn(&run_cmd.step);
}