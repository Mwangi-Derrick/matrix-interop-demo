// build.zig
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

    // Link C++ implementation with rigorous optimization flags
    bench.addCSourceFiles(.{
        .files = &.{"cpp/matrix.cpp"},
        .flags = &.{
            "-std=c++17",
            "-O3",
            "-march=native",
            "-ffast-math",
            "-funroll-loops",
        },
    });
    bench.addIncludePath(b.path("cpp"));
    bench.linkSystemLibrary(cppRuntimeFor(target));

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
    const rust_lib_path = b.fmt(
        "rust/target/{s}/release/libmatrix_rs.a",
        .{rustTargetTriple(target)},
    );
    bench.addObjectFile(b.path(rust_lib_path));

    // Windows-specific libraries for Rust/C++ interop
    if (target.result.os.tag == .windows) {
        bench.linkSystemLibrary("user32");
        bench.linkSystemLibrary("kernel32");
        bench.linkSystemLibrary("ws2_32");
        bench.linkSystemLibrary("advapi32");
        bench.linkSystemLibrary("ntdll");
        bench.linkSystemLibrary("userenv");
        bench.linkSystemLibrary("shell32");
    }

    bench.linkLibC();
    b.installArtifact(bench);

    const run_cmd = b.addRunArtifact(bench);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the benchmark");
    run_step.dependOn(&run_cmd.step);

    // Manual 'clean' step - Corrected for Zig 0.15.2
    const clean_step = b.step("clean", "Remove build artifacts");
    clean_step.makeFn = struct {
        fn make(_: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
            const path = ".zig-cache";
            const path2 = "zig-out";
            std.fs.cwd().deleteTree(path) catch {};
            std.fs.cwd().deleteTree(path2) catch {};
        }
    }.make;
}
// Add support for apple's stdc++
fn cppRuntimeFor(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.os.tag) {
        .macos => "c++",
        else => "stdc++",
    };
}
// logic for auto detection at compile time.
fn rustTargetTriple(target: std.Build.ResolvedTarget) []const u8 {
    return switch (target.result.os.tag) {
        .linux => switch (target.result.cpu.arch) {
            .aarch64 => "aarch64-unknown-linux-gnu",
            .x86_64 => "x86_64-unknown-linux-gnu",
            else => unsupportedRustTarget(target),
        },
        .macos => switch (target.result.cpu.arch) {
            .aarch64 => "aarch64-apple-darwin",
            .x86_64 => "x86_64-apple-darwin",
            else => unsupportedRustTarget(target),
        },
        .windows => switch (target.result.cpu.arch) {
            .x86_64 => "x86_64-pc-windows-gnu",
            else => unsupportedRustTarget(target),
        },
        else => unsupportedRustTarget(target),
    };
}
// just in case someone run it on another os not like i know who will though haha
fn unsupportedRustTarget(target: std.Build.ResolvedTarget) noreturn {
    std.debug.panic(
        "unsupported target for Rust static library: {s}-{s}",
        .{
            @tagName(target.result.cpu.arch),
            @tagName(target.result.os.tag),
        },
    );
}
