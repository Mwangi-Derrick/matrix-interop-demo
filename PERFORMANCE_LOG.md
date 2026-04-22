# PERFORMANCE_LOG.md — The Benchmark Audit Trail

> *"Performance is not an accident. It is an engineered outcome, built one measurement at a time. And it must be reproducible, or it is not evidence."*

This document is the authoritative, step-by-step record of every code change, configuration adjustment, and benchmark result produced during the optimization of `matrix-lib`. It has been validated on two physically separate machines running different CPU architectures, operating systems, and compiler toolchains.

**The automated stage runner** (`run_benchmark_stages.sh`) means every number in this document can be re-derived by any engineer who clones the repository. Reproducing results yourself is strongly encouraged before drawing any conclusions.

---

## Machines and Environments

### Machine A — Intel Core i5-6300U (Primary Development)

| Parameter | Value |
|:---|:---|
| **Contributor** | [@Mwangi-Derrick](https://github.com/Mwangi-Derrick) |
| **CPU** | Intel Core i5-6300U |
| **Microarchitecture** | Skylake (6th-gen Intel, 2015) |
| **CPU Clock** | 2.4 GHz base / 3.0 GHz boost |
| **Physical Cores** | 2 cores / 4 threads (Hyper-Threading) |
| **L1 Data Cache** | 32 KB per core |
| **L2 Cache** | 256 KB per core |
| **L3 Cache (LLC)** | 3 MB shared |
| **Cache Line Size** | 64 bytes = 16 × f32 |
| **SIMD Support** | SSE4.2, AVX2 (256-bit, 8 × f32) |
| **OS** | Windows 11 |
| **Shell** | MINGW64 / MSYS2 |
| **Zig Version** | 0.15.2 (internal LLVM 20.1.2) |
| **Rust Version** | 1.93.1 |
| **Rust Target** | `x86_64-pc-windows-gnu` |
| **GCC Version** | g++ 15.2.0 (x86_64-w64-mingw32) |

### Machine B — Apple M3 (Cross-Platform Validation)

| Parameter | Value |
|:---|:---|
| **Contributor** | [@million-in](https://github.com/million-in) |
| **CPU** | Apple M3 |
| **Microarchitecture** | ARM64 (aarch64-apple-darwin, 2024) |
| **CPU Clock** | ~3.0 GHz+ (performance cores) |
| **L1 Data Cache** | 128 KB per performance cluster |
| **L2 Cache** | ~4 MB per performance cluster |
| **L3 Cache (LLC)** | ~12–24 MB shared (estimated) |
| **Cache Line Size** | 64 bytes = 16 × f32 |
| **SIMD Support** | Neon / ASIMD (128-bit, 4 × f32), SVE-capable |
| **OS** | macOS |
| **Zig Version** | 0.15.2 |
| **Rust Version** | 1.93.1 |
| **Rust Target** | `aarch64-apple-darwin` |
| **Compiler** | Apple Clang / system g++ |

### Benchmark Workload (All Stages)

| Parameter | Value |
|:---|:---|
| **Matrix dimensions** | 1024 × 1024 |
| **Data type** | `f32` (32-bit single-precision float) |
| **Total FLOPs** | ≈ 2,147,483,648 (2.1 billion) |
| **Memory footprint (3 matrices)** | 3 × 4 MB = **12 MB** |
| **Timing method** | `std.time.milliTimestamp()` (wall clock, ms) |
| **Correctness check** | All three results within `0.001` tolerance per cell |

---

## Benchmark Methodology

All benchmarks use this measurement pattern in `bench/bench.zig`:

```zig
const start = std.time.milliTimestamp();
function_under_test(a.ptr, m, n, b.ptr, n, p, result.ptr);
const elapsed = std.time.milliTimestamp() - start;
```

Single-run measurement. For execution times >400ms, timer jitter (typically ±1–2ms) is negligible. The correctness check:

```zig
var all_match = true;
for (0..m * p) |i| {
    if (@abs(result_zig[i] - result_rust[i]) > 0.001 or
        @abs(result_zig[i] - result_cpp[i]) > 0.001) {
        all_match = false;
        break;
    }
}
```

The 0.001 tolerance is necessary because `-ffast-math` and equivalent flags allow different compilers to reorder floating-point operations, producing bitwise-different but mathematically equivalent results.

---

## Automated Stage Runner

`run_benchmark_stages.sh` — contributed by [@million-in](https://github.com/million-in) — uses `git worktree` to check out each historical stage commit and run the benchmark without modifying the working tree.

```bash
# Usage (auto-detects host platform):
./run_benchmark_stages.sh

# Example output on Apple M3:
Host target: aarch64-apple-darwin
=== stage1 (f81426b) ===
Zig: 1020 ms | Rust: 1081 ms | C++: 1284 ms | Results match: true
=== stage2 (906609d) ===
Zig: 1026 ms | Rust: 1084 ms | C++: 1263 ms | Results match: true
=== stage3 (c7c6d4c) ===
Zig: 89 ms   | Rust: 83 ms   | C++: 83 ms   | Results match: true
=== stage4 (32f7d90) ===
Zig: 144 ms  | Rust: 126 ms  | C++: 119 ms  | Results match: true
```

---

## Stage 1 — The Naive Baseline

### Configuration

| Parameter | Machine A (i5-6300U) | Machine B (M3) |
|:---|:---|:---|
| Zig flags | `-Doptimize=ReleaseFast` | `-Doptimize=ReleaseFast` |
| Rust flags | `cargo build --release` | `cargo build --release` |
| C++ flags | `-O3` (Zig default) | `-O3` |
| CPU targeting | Generic x86-64 | Generic ARM64 |
| Fast-math | Zig: yes (ReleaseFast default). C++/Rust: no | Same |
| Loop order | `(i, j, k)` all three | `(i, j, k)` all three |

### The Code

**Zig** (`zig/matrix.zig`):
```zig
export fn zig_matrix_multiply(
    a_ptr: [*]f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]f32, b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void {
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
```

**Rust** (`rust/src/matrix.rs`):
```rust
#[no_mangle]
pub extern "C" fn rust_matrix_multiply(
    a_ptr: *const f32, a_rows: usize, a_cols: usize,
    b_ptr: *const f32, b_rows: usize, b_cols: usize,
    result_ptr: *mut f32,
) {
    let a = unsafe { std::slice::from_raw_parts(a_ptr, a_rows * a_cols) };
    let b = unsafe { std::slice::from_raw_parts(b_ptr, b_rows * b_cols) };
    let result = unsafe { std::slice::from_raw_parts_mut(result_ptr, a_rows * b_cols) };
    for i in 0..a_rows {
        for j in 0..b_cols {
            let mut sum = 0.0f32;
            for k in 0..a_cols {
                sum += a[i * a_cols + k] * b[k * b_cols + j];
            }
            result[i * b_cols + j] = sum;
        }
    }
}
```

**C++** (`cpp/matrix.cpp`):
```cpp
extern "C" {
    void cpp_matrix_multiply(
        const float* a_ptr, size_t a_rows, size_t a_cols,
        const float* b_ptr, size_t b_rows, size_t b_cols,
        float* result_ptr
    ) {
        for (size_t i = 0; i < a_rows; ++i) {
            for (size_t j = 0; j < b_cols; ++j) {
                float sum = 0.0f;
                for (size_t k = 0; k < a_cols; ++k) {
                    sum += a_ptr[i * a_cols + k] * b_ptr[k * b_cols + j];
                }
                result_ptr[i * b_cols + j] = sum;
            }
        }
    }
}
```

### Results

| Language | Machine A (i5-6300U) | Machine B (M3) |
|:---:|:---:|:---:|
| **Zig** | 10,414 ms | 1,020 ms |
| **Rust** | 12,826 ms | 1,081 ms |
| **C++** | 12,820 ms | 1,284 ms |

### Analysis

**i5-6300U**: Zig led by ~20%. All three implementations share the identical `(i,j,k)` loop pattern with identical cache miss behavior. The gap is entirely due to Zig's `ReleaseFast` defaults including implicit fast-math relaxations, while C++ and Rust compiled without `-march=native` or `-ffast-math`.

**M3**: An interesting reversal — C++ is *slowest* (1,284ms) and Zig is fastest (1,020ms). On M3 with a generic ARM64 target, the C++ compiler's default optimizations were slightly less effective than Zig's aggressive defaults. All three are within 25% of each other — much tighter than on i5.

**Absolute M3 vs i5 ratio**: ~10× faster on M3 for this workload. This comes from the M3's larger caches (128KB L1 vs 32KB), wider execution engine, and higher sustained clock frequency.

**The Lesson**: Do not interpret Stage 1 as "Zig is faster than C++ and Rust." Interpret it as "Zig's default optimization profile is more aggressive for this specific workload." Compiler defaults are not equal. This means nothing until we normalize the configurations.

---

## Stage 2 — Toolchain Standardization

### What Changed

**`build.zig`** C++ compilation flags updated:
```zig
bench.addCSourceFiles(.{
    .files = &.{"cpp/matrix.cpp"},
    .flags = &.{
        "-std=c++17",
        "-O3",
        "-march=native",    // NEW: use all CPU-specific instructions (AVX2/Neon)
        "-ffast-math",      // NEW: allow FP reordering for SIMD
        "-funroll-loops",   // NEW: explicit loop unroll hint
    },
});
```

**Rust** build command:
```bash
RUSTFLAGS="-C target-cpu=native" cargo build --release --target x86_64-pc-windows-gnu
```

**Zig** build command:
```bash
zig build run -Doptimize=ReleaseFast -Dtarget=native
```

### The Hypothesis

By normalizing compiler configurations — giving each toolchain equivalent access to CPU-specific instructions and floating-point relaxation — we expected performance to converge.
### Results

| Language | Machine A (i5-6300U) | Delta (i5) | Machine B (M3) | Delta (M3) |
|:---:|:---:|:---:|:---:|:---:|
| **Zig** | 13,466 ms | **+29%** (regression) | 1,026 ms | +0.6% (flat) |
| **Rust** | 12,685 ms | -1% (flat) | 1,084 ms | +0.3% (flat) |
| **C++** | 10,671 ms | **-17%** (new leader) | 1,263 ms | -1.6% (flat) |

### Analysis

**i5-6300U**: C++ won the standardization race. `-ffast-math` + `-march=native` unlocked AVX2 code generation (256-bit SIMD instead of SSE2 128-bit). Even on the cache-miss-heavy naive loop, wider SIMD reduced instruction count.

Zig *regressed* by 29%. Passing `-Dtarget=native` overrode Zig's carefully calibrated `ReleaseFast` heuristics with explicit Skylake-targeted settings that happened to make the optimizer choose different, slower code generation paths. This is a known LLVM behavior: explicit `target-cpu=native` can disrupt cost model calibration in unexpected ways.

**M3**: Everything was essentially flat — less than 2% change in any direction. Why? Because on the M3:
1. All three compilers' default ARM64 targets were already reasonably well-tuned for Apple Silicon.
2. The dominant bottleneck (stride access causing cache misses) was still present. No amount of vectorization help overcomes a cache miss storm — you can't SIMD your way out of waiting for RAM.

**The Lesson**: Compiler flags can change the leader on a memory-compute-balanced workload. But when the workload is purely **memory-bandwidth limited** (as Stage 1/2 are due to stride access), flags matter much less than access pattern. You cannot SIMD your way out of a cache miss storm.

---

## Stage 3 — The Hardware Sympathy Breakthrough

### What Changed

**Loop order changed from `(i, j, k)` to `(i, k, j)`** in all three implementations. The result matrix is now pre-zeroed and accumulated across k-iterations. Rust additionally switched from safe slices to raw pointers, eliminating all bounds check overhead.

**Zig** (`zig/matrix.zig`):
```zig
export fn zig_matrix_multiply(
    a_ptr: [*]const f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]const f32, _b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void {
    _ = _b_rows;
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;

    @memset(result_ptr[0 .. m * p], 0);

    for (0..m) |i| {
        for (0..n) |k| {
            const a_val = a_ptr[i * n + k];  // hoisted to register
            for (0..p) |j| {
                result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
            }
        }
    }
}
```

**Rust** (`rust/src/matrix.rs`) — switched to unsafe raw pointers:
```rust
#[no_mangle]
pub unsafe extern "C" fn rust_matrix_multiply(
    a_ptr: *const f32, a_rows: usize, a_cols: usize,
    b_ptr: *const f32, _b_rows: usize, b_cols: usize,
    result_ptr: *mut f32,
) {
    std::ptr::write_bytes(result_ptr, 0, a_rows * b_cols);

    for i in 0..a_rows {
        for k in 0..a_cols {
            let a_val = *a_ptr.add(i * a_cols + k);
            for j in 0..b_cols {
                *result_ptr.add(i * b_cols + j) += a_val * *b_ptr.add(k * b_cols + j);
            }
        }
    }
}
```

**C++** (`cpp/matrix.cpp`):
```cpp
extern "C" {
    void cpp_matrix_multiply(
        const float* a_ptr, size_t a_rows, size_t a_cols,
        const float* b_ptr, size_t _b_rows, size_t b_cols,
        float* result_ptr
    ) {
        std::memset(result_ptr, 0, a_rows * b_cols * sizeof(float));

        for (size_t i = 0; i < a_rows; ++i) {
            for (size_t k = 0; k < a_cols; ++k) {
                float a_val = a_ptr[i * a_cols + k];
                for (size_t j = 0; j < b_cols; ++j) {
                    result_ptr[i * b_cols + j] += a_val * b_ptr[k * b_cols + j];
                }
            }
        }
    }
}
```

### The Hypothesis

By making the innermost loop (`j`) iterate over sequential memory addresses in both B and Result, we eliminate the stride-access pattern that was causing cache misses. We expect significant improvements across all languages because the bottleneck (RAM latency) is being removed.

### Results

| Language | Machine A (i5) Stage 2 | Machine A (i5) Stage 3 | Speedup | Machine B (M3) Stage 2 | Machine B (M3) Stage 3 | Speedup |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Zig** | 13,466ms | **865ms** | **15.6×** | 1,026ms | **89ms** | **11.5×** |
| **Rust** | 12,685ms | **785ms** | **16.2×** | 1,084ms | **83ms** | **13.1×** |
| **C++** | 10,671ms | **419ms** | **25.5×** | 1,263ms | **83ms** | **15.2×** |

### Analysis

Every language improved by 11–25× in a single code change. This is the most decisive result in the project: **the access pattern change dominated everything else done in Stage 1 and Stage 2 combined.**

**Why C++ led on i5 but languages converged on M3**:

On the i5, C++ at 419ms was 2× faster than Zig at 865ms. The gap came from C++'s `-ffast-math` enabling full AVX2 vectorization (8 floats per instruction) while Zig's LLVM passes generated slightly less optimal vector code for this specific pattern on Skylake.

On the M3, Rust and C++ tied at 83ms while Zig was at 89ms — within 7%. The M3's microarchitecture advantages (wider execution, larger L1/L2) compensated for the code quality differences that were visible on Skylake.

**Implication**: If you only benchmark on modern hardware, you may miss 2× performance differences that would manifest on older deployment hardware. The language/compiler gap was real on Skylake (2015). The M3 (2024) was powerful enough to hide it.

**The absolute gap**: M3 achieved ~83ms where the i5 achieved ~419ms for C++ — roughly **5× better**. For Zig: ~89ms vs ~865ms — roughly **10× better**. The M3's architectural advantages are more pronounced for code that is already well-optimized than for cache-miss-heavy code (Stage 1 showed only a ~10× gap too, but for different reasons).

**The Lesson**: One algorithmic change delivered 11–25× improvement across two CPU architectures separated by nearly a decade. Compiler flags across the same algorithm delivered at most 17% on i5, and near-zero on M3. **Access pattern is the lever. Everything else is fine-tuning.**

---

## Stage 4 — Cache Blocking / Tiling

### What Changed

Implemented 64×64 cache-blocked loops in all three languages. Also updated `rust/Cargo.toml` for maximum Rust optimization:

```toml
[profile.release]
opt-level = 3
lto = "fat"              # Cross-crate link-time optimization
codegen-units = 1        # Whole-program optimization
panic = "abort"          # Remove unwinding machinery
overflow-checks = false  # No integer overflow detection
incremental = false      # Maximize optimization over build speed
```

**Zig** (`zig/matrix.zig`):
```zig
pub const BLOCK_SIZE = 64;

export fn zig_matrix_multiply(
    a_ptr: [*]const f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]const f32, _b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void {
    _ = _b_rows;
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;
    @memset(result_ptr[0 .. m * p], 0);

    var ii: usize = 0;
    while (ii < m) : (ii += BLOCK_SIZE) {
        var kk: usize = 0;
        while (kk < n) : (kk += BLOCK_SIZE) {
            var jj: usize = 0;
            while (jj < p) : (jj += BLOCK_SIZE) {
                var i = ii;
                while (i < @min(ii + BLOCK_SIZE, m)) : (i += 1) {
                    var k = kk;
                    while (k < @min(kk + BLOCK_SIZE, n)) : (k += 1) {
                        const a_val = a_ptr[i * n + k];
                        var j = jj;
                        while (j < @min(jj + BLOCK_SIZE, p)) : (j += 1) {
                            result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
                        }
                    }
                }
            }
        }
    }
}
```

**Rust** (`rust/src/matrix.rs`):
```rust
use std::cmp::min;
const BLOCK_SIZE: usize = 64;

#[no_mangle]
pub unsafe extern "C" fn rust_matrix_multiply(
    a_ptr: *const f32, a_rows: usize, a_cols: usize,
    b_ptr: *const f32, _b_rows: usize, b_cols: usize,
    result_ptr: *mut f32,
) {
    std::ptr::write_bytes(result_ptr, 0, a_rows * b_cols);
    for ii in (0..a_rows).step_by(BLOCK_SIZE) {
        for kk in (0..a_cols).step_by(BLOCK_SIZE) {
            for jj in (0..b_cols).step_by(BLOCK_SIZE) {
                let i_end = min(ii + BLOCK_SIZE, a_rows);
                for i in ii..i_end {
                    let k_end = min(kk + BLOCK_SIZE, a_cols);
                    for k in kk..k_end {
                        let a_val = *a_ptr.add(i * a_cols + k);
                        let j_end = min(jj + BLOCK_SIZE, b_cols);
                        for j in jj..j_end {
                            *result_ptr.add(i * b_cols + j) += a_val * *b_ptr.add(k * b_cols + j);
                        }
                    }
                }
            }
        }
    }
}
```

**C++** (`cpp/matrix.cpp`):
```cpp
#define BLOCK_SIZE 64

extern "C" {
    void cpp_matrix_multiply(
        const float* a_ptr, size_t a_rows, size_t a_cols,
        const float* b_ptr, size_t _b_rows, size_t b_cols,
        float* result_ptr
    ) {
        std::memset(result_ptr, 0, a_rows * b_cols * sizeof(float));

        for (size_t ii = 0; ii < a_rows; ii += BLOCK_SIZE) {
            for (size_t kk = 0; kk < a_cols; kk += BLOCK_SIZE) {
                for (size_t jj = 0; jj < b_cols; jj += BLOCK_SIZE) {
                    for (size_t i = ii; i < std::min(ii+BLOCK_SIZE, a_rows); ++i) {
                        for (size_t k = kk; k < std::min(kk+BLOCK_SIZE, a_cols); ++k) {
                            float a_val = a_ptr[i * a_cols + k];
                            for (size_t j = jj; j < std::min(jj+BLOCK_SIZE, b_cols); ++j) {
                                result_ptr[i * b_cols + j] += a_val * b_ptr[k * b_cols + j];
                            }
                        }
                    }
                }
            }
        }
    }
}
```

### Also Changed: `Cargo.toml` — Maximum Rust Optimization Profile

```toml
[profile.release]
opt-level = 3
lto = "fat"              # Maximum Link-Time Optimization: cross-crate inlining
codegen-units = 1        # Single codegen unit: allows whole-program optimization
panic = "abort"          # Remove stack unwinding machinery (smaller, faster binary)
overflow-checks = false  # Disable integer overflow detection in release
incremental = false      # Disable incremental compilation for maximum optimization
```

**`lto = "fat"`**: Link-Time Optimization runs an additional optimization pass across all compiled units after they are linked together. "fat" LTO includes all LLVM bitcode in the compiled artifacts and runs a full global optimization. This allows inlining across crate boundaries, dead code elimination that spans modules, and inter-procedural constant propagation.

### The Hypothesis

For 1024×1024 matrices, even the sequential `(i,k,j)` loop may experience some L3 cache pressure (Matrix B = 4 MB > L3 = 3 MB). By tiling into 64×64 blocks, we keep the active working set within L2 (each block = 16 KB, three blocks = 48 KB < 256 KB L2). This should reduce L3 misses and further improve throughput.


### Results

| Language | i5 Stage 3 | i5 Stage 4 | i5 Delta | M3 Stage 3 | M3 Stage 4 | M3 Delta |
|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **C++** | 419ms | 401ms | **-4%** | 83ms | 119ms | **+43%** |
| **Rust** | 785ms | 647ms | **-17%** | 83ms | 126ms | **+52%** |
| **Zig** | 865ms | 1,367ms | **+58%** | 89ms | 144ms | **+62%** |

### Analysis

This stage produced the most nuanced and instructive results in the entire project.

**i5-6300U — Mixed outcomes**: C++ and Rust improved; Zig regressed severely.

C++ (-4%): Already near compute-bound in Stage 3. Tiling provided marginal L2/L3 cache benefit but the overhead of extra loop variables and `std::min()` calls at block boundaries roughly offset it. Net: approximately flat.

Rust (-17%): Rust's LLVM backend recognized the `step_by(BLOCK_SIZE)` range pattern and the bounded inner loops (`ii..min(ii+BLOCK_SIZE, a_rows)`) as analyzable. LLVM proved these loops were safe to vectorize as 64-iteration inner loops and emitted efficient code. Additionally, `lto = "fat"` enabled global optimizations across the binary.

Zig (+58%): The severe regression comes from LLVM auto-vectorization analysis failure. Stage 3's inner loop:
```zig
for (0..p) |j| { ... }  // clean, bounded, analyzable
```
was trivially vectorizable — fixed trip count (1024), sequential pointers, no aliasing concerns. LLVM generated AVX2 code.

Stage 4's inner loop:
```zig
while (j < @min(jj + BLOCK_SIZE, p)) : (j += 1) { ... }
```
has a `while` construct with a runtime-computed bound (`@min(jj + BLOCK_SIZE, p)`). LLVM must prove the trip count is consistent, prove the pointers are non-aliasing despite the complex indexing, and prove the vectorized version produces equivalent results. This analysis fails. LLVM falls back to scalar code. Scalar code × complex 6-level loop structure × loss of SIMD = 58% slower.

**M3 — Universal regression**: Every language got slower on M3 with tiling. This is the most important cross-platform finding in Stage 4.

Why? The M3's L3 cache is large enough (~12–24MB estimated) that Matrix B (4MB) fits comfortably. In Stage 3, the M3's working set for a single result row was already largely in L3, and the hardware prefetcher was feeding L1/L2 efficiently. There were few L3 misses to eliminate.

Tiling's overhead (6 nested loops, min() calls, more complex pointer arithmetic) exceeded the benefit of the marginal cache improvement it provided on M3.

**The cross-architecture Zig regression magnitude**: i5 +58%, M3 +62%. Nearly identical percentages on different architectures, OSes, and CPU generations. This confirms the regression is entirely in LLVM's optimizer (which runs before the backend), not in hardware behavior. LLVM fails to vectorize Zig's tiled code on both x86_64 and ARM64 backends, for the same logical reason.

**The Lesson**: Cache blocking is a hardware-specific optimization. Its benefit depends on whether you are genuinely L3-cache-limited. On a 2015 laptop with a 3MB L3, tiling 4MB matrices helps. On a 2024 M3 with a much larger cache, the same workload is not L3-limited, and tiling only adds overhead. The "optimal" block size should be computed as `sqrt(L1_size / 3 / sizeof(f32))` for a given machine — a different answer on every CPU. There is no universal 64. **Always tune to the deployment target.**

---

## Complete Summary — All Stages, All Machines

> **Methodology**: Results below are from `run_benchmark_stages.sh`, which runs all stages sequentially on the same machine. Each stage uses its immutable stage-matched kernels with dynamically calculated block sizes. Numbers are median of 5 timed runs after warmup.

### Intel Core i5-6300U — Local (3 MB L3, block sizes: L1=48, L2=144, L3=496)

| Stage | Algorithm | Zig | Rust | C++ |
|:---|:---|:---:|:---:|:---:|
| 1 | Naive (i,j,k) — default flags | 7,911ms | 7,986ms | 8,454ms |
| 2 | Naive (i,j,k) — normalized flags | 8,943ms | 8,650ms | 9,498ms |
| 3 | Optimized (i,k,j) — normalized flags | 273ms | 245ms | **232ms** |
| 4 | Tiled l1_block×l1_block (i,k,j) — normalized flags | 226ms | 218ms | **208ms** |
| 5 | Hierarchical funnel + 4×4 SIMD µ-kernel | 274ms | 380ms | 317ms |

### GitHub Actions CI Runner (32 MB L3, block sizes: L1=48, L2=200, L3=1624)

| Stage | Algorithm | Zig | Rust | C++ |
|:---|:---|:---:|:---:|:---:|
| 1 | Naive (i,j,k) — default flags | 7,353ms | 5,346ms | 7,464ms |
| 2 | Naive (i,j,k) — normalized flags | 7,915ms | 5,561ms | 8,049ms |
| 3 | Optimized (i,k,j) — normalized flags | **62ms** | **62ms** | **70ms** |
| 4 | Tiled l1_block×l1_block (i,k,j) — normalized flags | 171ms | 166ms | 172ms |
| 5 | Hierarchical funnel + 4×4 SIMD µ-kernel | 198ms | 212ms | 217ms |

### Apple M3 (aarch64-apple-darwin) — Historical, hardcoded BLOCK_SIZE=64

| Stage | Algorithm | Zig | Rust | C++ |
|:---|:---|:---:|:---:|:---:|
| 1 | Naive (i,j,k) — default flags | 1,020ms | 1,081ms | 1,284ms |
| 2 | Naive (i,j,k) — normalized flags | 1,026ms | 1,084ms | 1,263ms |
| 3 | Optimized (i,k,j) — normalized flags | **89ms** | **83ms** | **83ms** |
| 4 | Tiled 64×64 — normalized flags | 144ms | 126ms | 119ms |

*M3 Stage 5 results are pending.*

### Key Observations

**Stage 4 improved dramatically.** The old PERFORMANCE_LOG reported Zig at 1,367ms with a hardcoded `BLOCK_SIZE=64`. That block size overflows L1 (64²×3×4 = 49KB > 32KB L1), causing cache thrashing. The dynamic `l1_block=48` (48²×3×4 = 27KB < 32KB) fits perfectly. Result: Zig Stage 4 dropped from 1,367ms → 226ms. **The "Stage 4 regression" was a misconfigured block size, not an auto-vectorization failure.**

**Stage 5 is slower than Stage 4.** The 4×4 micro-kernel uses `@Vector(4, f32)` (128-bit SSE). But the i5-6300U supports AVX2 (256-bit, 8 floats at a time). The auto-vectorizer in Stages 3-4 generates **8-wide** code for free. Stage 5's hand-written **4-wide** SIMD has half the throughput, plus the overhead of hierarchical (12-nested) loop structure. On the CI runner (32MB L3), tiling adds pure overhead since the entire working set already fits in cache.

**The honest conclusion**: explicit SIMD only helps when it matches or exceeds the auto-vectorizer's width. A `@Vector(4, f32)` micro-kernel on AVX2 hardware is a **pessimization**. The correct fix is widening to `@Vector(8, f32)` — this is the next optimization target.

---

## Known Limitations

### What These Benchmarks Don't Measure

**Single-run measurements**: Each result is a single wall-clock measurement. Statistical averaging over multiple runs would reduce noise but would also require much longer documentation. For runs >400ms, single-run variance is typically <1%.

**Background load**: System background processes (antivirus, OS services, browser) can affect results. Measurements were taken during low-activity periods but were not taken in an isolated single-process environment.

**Frequency scaling**: Both CPUs use dynamic frequency scaling (Turbo Boost / Performance Mode). Results may vary with thermal throttling state.

**Single matrix size**: All benchmarks use 1024×1024. Results at 512×512 or 2048×2048 would show different tiling behavior, particularly on M3 where the larger cache changes the cache-miss profile significantly.

 **Memory bandwidth ceiling**: We haven't measured whether we're hitting the CPU's memory bandwidth limit. For Stage 3 results, the bottleneck has shifted from latency (cache misses) to compute (how fast we can do the FMAs). But we haven't confirmed this with hardware performance counters.

**Binary size comparison**: Larger binaries have worse instruction cache utilization. We haven't measured the compiled binary sizes for each stage.


*Warm vs. cold cache**: All benchmarks start with a "warm" cache — the matrices are allocated and populated before timing begins. Cold-start performance (first access after boot) would show different characteristics.

---

## Stage 5 — Hierarchical Cache Funnel + Register SIMD Micro-kernel

### What Changed

Three fundamental changes, applied to all three languages simultaneously:

1. **Hierarchical cache blocking** — replaced the single 64×64 tile with a 3-level funnel: L3 → L2 → L1. Block sizes are computed at runtime from the host CPU's actual cache sizes (detected via OS APIs).

2. **4×4 register micro-kernel** — the innermost computation unit processes a 4×4 tile of C using 4 SIMD vector registers. This removes 16 elements of C from the cache hierarchy entirely — they live in CPU registers for the duration of the k-loop.

3. **Explicit SIMD vectors** — bypassed LLVM's auto-vectorizer entirely. Zig uses `@Vector(4, f32)`, C++ uses `__attribute__((vector_size(16)))`, and Rust uses unrolled scalar code with `__restrict`-equivalent aliasing guarantees.

### Why This Solves Stage 4's Regression

Stage 4's regression was caused by LLVM's auto-vectorizer failing to analyze the `@min()` bounded while-loops. Stage 5 eliminates the auto-vectorizer as a variable by writing the SIMD operations explicitly:

```zig
// Stage 4 (broken): relies on auto-vectorizer
while (j < @min(jj + BLOCK_SIZE, p)) : (j += 1) {
    result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
}

// Stage 5 (fixed): explicit SIMD, no auto-vectorization needed
const b_vec: @Vector(4, f32) = b_row[jj..][0..4].*;
c_row0 += @as(@Vector(4, f32), @splat(a_ptr[i * n + kk + 0])) * b_vec;
```

### Cache Utilization Strategy

The micro-kernel's 4×4 C tile lives entirely in registers, freeing L1 for A and B data exclusively. This enabled aggressive cache fill percentages:

| Cache Level | Stage 4 (implied) | Stage 5 |
|:---|:---:|:---:|
| L1 (32 KB) | ~40% (64×64 = 49 KB, overflows) | **100%** (C tile in registers) |
| L2 (256 KB) | N/A (single-level) | **95%** |
| L3 (3 MB) | N/A (single-level) | **95%** |

Runtime-detected block sizes on i5-6300U: `L1=48, L2=144, L3=496`.

### The Code

**Zig** (`zig/matrix_stage5.zig`) — 4×4 register micro-kernel with `@Vector(4, f32)`:
```zig
// Innermost micro-kernel: processes a 4×4 C tile using 4 SIMD registers
var c_row0: @Vector(4, f32) = c_row_slice0[0..4].*;
var c_row1: @Vector(4, f32) = c_row_slice1[0..4].*;
var c_row2: @Vector(4, f32) = c_row_slice2[0..4].*;
var c_row3: @Vector(4, f32) = c_row_slice3[0..4].*;

var kk = k_start;
while (kk < k_end) : (kk += 1) {
    const b_vec: @Vector(4, f32) = b_row[kk * p + j_start ..][0..4].*;
    c_row0 += @as(@Vector(4, f32), @splat(a_ptr[i0 * n + kk])) * b_vec;
    c_row1 += @as(@Vector(4, f32), @splat(a_ptr[i1 * n + kk])) * b_vec;
    c_row2 += @as(@Vector(4, f32), @splat(a_ptr[i2 * n + kk])) * b_vec;
    c_row3 += @as(@Vector(4, f32), @splat(a_ptr[i3 * n + kk])) * b_vec;
}
// Write back from registers to memory (4 stores, not 16)
c_row_slice0[0..4].* = c_row0;
c_row_slice1[0..4].* = c_row1;
c_row_slice2[0..4].* = c_row2;
c_row_slice3[0..4].* = c_row3;
```

**C++** (`cpp/matrix_stage5.cpp`) — vector extensions with `__restrict`:
```cpp
typedef float v4f __attribute__((vector_size(16)));

// The __restrict qualifier tells the compiler that a_ptr, b_ptr,
// and result_ptr do NOT alias each other. Without this, the compiler
// cannot keep values in registers across iterations.
void cpp_matrix_multiply(
    const float* __restrict a_ptr, ...,
    float* __restrict result_ptr, ...) {

    v4f c00, c10, c20, c30;
    // ... load C tile from memory into vector registers
    for (size_t kk = k_start; kk < k_end; ++kk) {
        v4f b_vec = *(const v4f*)&b_ptr[kk * b_cols + j_start];
        v4f a0 = {a_val0, a_val0, a_val0, a_val0};
        c00 += a0 * b_vec;
        // ... repeat for c10, c20, c30
    }
}
```

**Rust** (`rust/src/matrix_stage5.rs`) — unrolled scalar with LLVM aliasing guarantees:
```rust
// Rust's ownership model guarantees no aliasing between a_ptr, b_ptr, result_ptr.
// LLVM leverages this to keep accumulators in registers.
let mut c00 = *result_ptr.add(i0 * b_cols + j_start + 0);
// ... load 16 C values into local variables (registers)
for kk in k_start..k_end {
    let b0 = *b_ptr.add(kk * b_cols + j_start + 0);
    // ... FMA across 4 rows × 4 columns
    c00 += a_val_i0 * b0;
}
*result_ptr.add(i0 * b_cols + j_start + 0) = c00;
```

### Results

| Language | i5 Stage 4 | i5 Stage 5 | Delta | Speedup |
|:---:|:---:|:---:|:---:|:---:|
| **Zig** | 1,367ms | **135ms** | **-90%** | **10.1×** |
| **Rust** | 647ms | **135ms** | **-79%** | **4.8×** |
| **C++** | 401ms | **152ms** | **-62%** | **2.6×** |

### Analysis

**Zig**: The most dramatic improvement in the entire project. From worst performer at 1,367ms (Stage 4 auto-vectorization failure) to **fastest** at 135ms. The explicit `@Vector(4, f32)` bypassed the auto-vectorizer entirely, and the hierarchical cache funnel eliminated L3 cache thrashing. **10× speedup from a code-level fix, not a flags fix.**

**Rust**: Strong improvement from 647ms to 135ms. Rust's strict ownership model (no pointer aliasing by construction) meant LLVM could keep the 16 C-tile accumulators in registers without needing explicit SIMD types — though the code was carefully unrolled to hint at register promotion.

**C++**: Improved from 401ms to 152ms. C++ required `__restrict` on all three pointer parameters to achieve register promotion. Without `__restrict`, the compiler must assume that writing to `result_ptr` might modify data pointed to by `a_ptr` or `b_ptr`, forcing it to re-load values from memory on every iteration.

**Convergence**: All three languages are now within **12% of each other** (135–152ms). Compare to Stage 4 where the gap was **3.4×** (401ms to 1,367ms). The explicit micro-kernel eliminated the compiler as a performance variable — the same hardware physics dominates equally in all three languages.

**The Lesson**: When compiler auto-vectorization fails (as it did for all three languages to varying degrees in Stage 4's complex loop nest), the fix is not better flags or compiler hints. The fix is **writing the SIMD operations yourself**. Every systems language provides this capability: Zig's `@Vector`, Rust's `std::arch` / unrolled scalars, C++'s vector extensions / intrinsics. Taking control of the innermost loop's register usage is the single most impactful optimization available after the access pattern is correct.

---

## Next Measurements — Future Stages

**Stage 6: Matrix Packing**
Copy tiles into contiguous memory buffers before computation to eliminate TLB misses and guarantee perfect cache line alignment:
```zig
// Pack B tile into contiguous buffer (no stride in the packed copy)
var pack_b: [BLOCK * BLOCK]f32 = undefined;
for (0..tile_k) |tk| {
    @memcpy(pack_b[tk * tile_j..][0..tile_j], b_ptr[kk + tk * p + jj..][0..tile_j]);
}
```

**Stage 7: Parallelism**
```zig
// Distribute outer 'i' loop across threads
const thread_count = std.Thread.getCpuCount() catch 1;
```

**Stage 8: Cross-Language FFI Integration Examples**
- Python via `ctypes`: `lib = ctypes.CDLL("./bench.dll")`
- Go via `cgo`: `// #include "matrix.h"`
- Node.js via `node-ffi-napi`

---

## 🧠 Benchmark Variance & Cache Effects (Important Insight)

During repeated benchmarking runs, performance results vary significantly even when the code and inputs remain unchanged.

Example observed results:

Zig:  748 ms → 158 ms → 178 ms → 164 ms → 176 ms  
Rust: 719 ms → 174 ms → 186 ms → 211 ms → 234 ms  
C++:  367 ms → 152 ms → 170 ms → 182 ms

### Why this happens

Matrix multiplication performance is heavily influenced by **CPU state**, not just code:

-   **Cache warmth (L1/L2/L3):**  
    Data may already be cached from previous runs, making execution significantly faster.
-   **Cache eviction:**  
    Background processes (browser, OS services) can evict hot data from cache, causing slowdowns.
-   **Branch predictor & prefetcher state:**  
    Modern CPUs “learn” memory access patterns over time, improving or degrading performance between runs.
-   **OS scheduling noise:**  
    CPU time is shared with system processes, introducing variability.

* * *

### Key Insight

> Performance is not just about computation speed — it is about **memory locality and CPU cache reuse**.

Matrix multiplication performance is dominated by:

-   How efficiently data fits into cache lines (typically 64 bytes)
-   Whether memory access is sequential or strided
-   How often the CPU must fetch from L2/L3 or RAM

* * *

### Practical Conclusion

Small code changes may not matter as much as:

-   Memory access patterns
-   Cache reuse efficiency
-   Data layout in memory

In high-performance systems, the goal is:

> **Minimize cache misses and maximize reuse per cache line fetched.**

* * *

### Implication for this project

This benchmark demonstrates that:

-   Language choice alone is not the primary performance factor
-   Compiler optimizations and memory access patterns dominate runtime behavior
-   Real-world performance must be measured across multiple runs, not single executions

*This log is the primary evidence base for all claims made in README.md and DEEP_DIVE.md. Every number in this document corresponds to a real measurement made on real hardware under the specified conditions. Reproducing these results on different hardware will yield different absolute values but the same relative patterns.*

*This document documents results from two machines separated by nearly a decade of CPU design evolution. All claims are falsifiable by running `./run_benchmark_stages.sh` on your own hardware.*