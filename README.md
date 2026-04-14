# Matrix-Lib: Systems-Level Interop & Performance Analysis

An empirical exploration of modern systems programming, evaluating how **Zig**, **Rust**, and **C++** optimize high-compute workloads in a unified, multi-language build environment.

```text
    [ Infrastructure Layer ]
           |
    +------+------+------+
    |      |      |      |
  [Zig]  [Rust] [C++]  (O(n³) Kernels)
    |      |      |
    +------+------+
           |
    [ Unified Build System (Zig) ]
```

## Abstract
This project analyzes the performance of naive $O(n^3)$ matrix multiplication across three LLVM-backed toolchains. This research demonstrates that "language speed" is often a proxy for toolchain configuration, specifically regarding SIMD vectorization and floating-point reordering.

---

## Comparative Performance: 1024x1024 Workload
Benchmarks performed on **x86_64-windows-gnu** (MSYS2/MinGW). Total operations: ~2.1 Billion FLOPs.

| Implementation | Execution Time | Performance Delta | Notes |
| :--- | :--- | :--- | :--- |
| **C++** | **10,671 ms** | **1.00x (Baseline)** | 🏆 Leader with `-ffast-math -march=native`. |
| **Rust** | **12,685 ms** | **1.19x** | Stable with LTO and `target-cpu=native`. |
| **Zig** | **13,466 ms** | **1.26x** | High variance depending on `-Dtarget` detection. |

### Performance Analysis: The "Standardization Flip"
Earlier iterations showed Zig in the lead, but rigorous standardization of C++ flags (`-ffast-math`) allowed `g++` to reclaim the performance crown.

1.  **The `-ffast-math` Impact**: C++'s lead is largely attributed to aggressive floating-point optimizations that allow the compiler to ignore strict IEEE 754 compliance in favor of SIMD throughput.
2.  **Toolchain Heuristics**: Zig's regression when moving to an explicit `native` target suggests that the internal LLVM heuristics for CPU detection can significantly sway results in tight arithmetic loops.
3.  **The "Safety" Tax**: Rust's consistent 12s performance shows the plateau of safe-but-optimized code. Even with bounds-check elision, the abstraction layer provides a highly predictable, if not "bleeding edge," execution time.

---

## Technical Insights
*   **Vectorization**: The delta between 10s and 13s is almost entirely due to how effectively the compiler unrolls the inner `k` loop and utilizes YMM/ZMM registers.
*   **Aliasing**: C++ with `-O3` and Zig both benefit from aggressive pointer analysis, while Rust relies on its unique borrow-checker-driven aliasing information.

---

## Build & Run
```bash
# 1. Prepare the Rust Engine
cd rust && RUSTFLAGS="-C target-cpu=native" cargo build --release --target x86_64-pc-windows-gnu && cd ..

# 2. Run the High-Performance Harness
zig build clean
zig build run -Doptimize=ReleaseFast -Dtarget=native
```

---

## Conclusion
Systems engineering is the art of **configuration**. This project proves that the choice between Zig, Rust, and C++ should be based on **developer ergonomics and safety models**, as the raw performance can be equalized or flipped through expert-level toolchain tuning.
