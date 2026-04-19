# matrix-lib: A Polyglot Systems Performance Journey

> _"In systems engineering, we don't just write code that works. We write code that vibrates with the hardware."_

---

```text
╔══════════════════════════════════════════════════════════════════════╗
║                    THE POLYGLOT ENGINE                               ║
║                                                                      ║
║   Your Application Code (Python / Go / TypeScript / Node.js)         ║
║          │                                                           ║
║          ▼                                                           ║
║   ┌──────────────────────────────────────────┐                       ║
║   │         C  A B I  B o u n d a r y        │  ← Zero-overhead      ║
║   └──────────────────────────────────────────┘     FFI calls         ║
║          │               │               │                           ║
║          ▼               ▼               ▼                           ║
║      ┌───────┐       ┌───────┐       ┌───────┐                       ║
║      │  Zig  │       │ Rust  │       │  C++  │  ← Compute Kernels    ║
║      │ 865ms │       │ 647ms │       │ 401ms │                       ║
║      └───────┘       └───────┘       └───────┘                       ║
║          │               │               │                           ║
║          └───────────────┼───────────────┘                           ║
║                          ▼                                           ║
║          ┌────────────────────────────────┐                          ║
║          │   Zig Build System (build.zig) │  ← Unified Orchestrator  ║
║          │   Compiles C++, links Rust     │                          ║
║          │   .a staticlib, resolves all   │                          ║
║          │   Windows system deps          │                          ║
║          └────────────────────────────────┘                          ║
║                          │                                           ║
║                          ▼                                           ║
║          ┌────────────────────────────────┐                          ║
║          │   Single Benchmark Binary      │                          ║
║          │   bench.exe                    │                          ║
║          └────────────────────────────────┘                          ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## What This Repository Is

This is not a typical "language comparison" project. Those are almost always misleading — they benchmark toy problems with inconsistent flags and declare a winner before the conversation even starts.

This is something different. This is a **recorded, auditable, step-by-step investigation** into what actually governs performance in low-level systems code. We used matrix multiplication as the probe, but the real subject under study is the relationship between your source code, the compiler's optimizer, and the CPU's memory subsystem.

We went from **~13,000 milliseconds** to **401 milliseconds** on the same 1024×1024 workload. We did it across three languages simultaneously. And we documented every step, every regression, and every hard-won lesson along the way.

The journey produced four major insights that apply to every high-performance system you will ever build:

1. **RAM is a flat, 1D tape.** Your 2D mental model of a matrix is a lie the language tells you for convenience. The moment you write code that fights this reality, you lose.
2. **Cache lines are the unit of memory currency.** The CPU doesn't buy floats from RAM one at a time. It buys 16 at once. If you only use 1 of those 16, you wasted 94% of your memory bandwidth.
3. **Compiler flags are load-bearing architecture.** `-ffast-math` is not cosmetic. It unlocks an entirely different class of machine code (AVX2 vectorization). Without it, your code and the machine code are nearly unrecognizable as siblings.
4. **Manual optimization can fight the compiler.** In Stage 4, adding cache-blocking code actually _regressed_ Zig by 58%. The compiler was auto-vectorizing the simple loop perfectly. Our "smart" manual tiling broke its ability to prove the loop was safe to vectorize.

If you absorb these four lessons, you will think differently about every loop you write for the rest of your career.

---

## Who Built This

An **Electrical and Electronic Engineering student at JKUAT** (Jomo Kenyatta University of Agriculture and Technology, Kenya), building production systems infrastructure on the side. The project emerged from a desire to learn Zig as a modern systems language and turned into a deeper investigation into compiler theory, CPU architecture, and the physics of memory access.

The CPU used for all benchmarks is an **Intel Core i5-6300U** (Skylake microarchitecture, 2 cores / 4 threads, 6th-generation Intel). This is a mid-range laptop chip — not a server, not a workstation. The results are entirely reproducible on consumer hardware.

---

## The Languages and What They Represent

### Zig — The Modern Systems Glue

Zig is the "new C." It gives you manual memory control, zero hidden allocations, and no runtime. What makes Zig unique in this project is that it serves **dual roles**: it is both one of the three compute kernels _and_ the build system that orchestrates the entire project. `build.zig` replaces `CMakeLists.txt`, `Makefile`, and shell scripts. It compiles C++ source files, links Rust `.a` static libraries, and resolves Windows system dependencies — all in one coherent, programmable build description.

Zig's `comptime` (compile-time execution) means that zero-cost abstractions aren't just a goal; they're enforced by the type system. There is no runtime cost for generic code in Zig.

### Rust — The Memory-Safe Performance Contender

Rust's ownership model gives the compiler a formally-verified understanding of pointer aliasing. In theory, this should allow extremely aggressive LLVM optimization. In practice, the safety abstractions (safe slices with implicit bounds checks) introduced overhead in Stage 1. Once we stripped those abstractions and worked with raw pointers in `unsafe` blocks (Stage 3), Rust found its footing and eventually achieved its best result with cache-blocked tiling in Stage 4 (647ms).

### C++ — The Veteran

C++ has decades of production use and its compiler ecosystem (GCC, Clang, MSVC) is extraordinarily mature. With the right flags (`-O3 -march=native -ffast-math -funroll-loops`), `g++ 15.2.0` consistently produced the fastest binary in this benchmark. This is not because C++ is "faster" as a language — it's because the GCC optimizer for this specific workload and this specific CPU has extremely well-tuned heuristics for loop unrolling and AVX2 code generation.

---

## Performance Results — The Full Picture

### Environment

| Factor          | Value                                 |
| :-------------- | :------------------------------------ |
| OS              | Windows 11 (MSYS2/MinGW64)            |
| CPU             | Intel Core i5-6300U (Skylake, x86_64) |
| L1 Cache        | 32 KB data / core                     |
| L2 Cache        | 256 KB / core                         |
| L3 Cache        | 3 MB shared                           |
| Cache Line Size | 64 bytes = 16 × f32                   |
| Zig Version     | 0.15.2                                |
| Rust Version    | 1.93.1 (x86_64-pc-windows-gnu)        |
| C++ Compiler    | g++ 15.2.0 (x86_64-w64-mingw32)       |

### Summary Table — 1024×1024 × 1024×1024 (≈2.1 billion FLOPs)

| Stage | What Changed                             |   Zig    |   Rust   |   C++    | Key Insight                        |
| :---- | :--------------------------------------- | :------: | :------: | :------: | :--------------------------------- |
| **1** | Naive `(i,j,k)` loops                    | 10,414ms | 12,826ms | 12,820ms | Default flags favor Zig            |
| **2** | Added `-march=native -ffast-math` to C++ | 13,466ms | 12,685ms | 10,671ms | Flags flip the leader              |
| **3** | Reordered to `(i,k,j)` loops             |  865ms   |  785ms   |  419ms   | **Algorithm dominates everything** |
| **4** | 64×64 cache-blocked tiling               | 1,367ms  |  647ms   |  401ms   | Manual opt can hurt the compiler   |

> **Total peak improvement over the naive baseline:**
>
> - C++: **32×** faster (12,820ms → 401ms)
> - Rust: **19.8×** faster (12,826ms → 647ms)
> - Zig (best): **13.3×** faster (10,414ms → 785ms in Stage 3)

---

## The Lessons Learned (Systems Mindset)

These are not abstract principles. These are observations made from real benchmark data, produced on real hardware, with real code changes tracked in the audit log.

### Lesson 1: Language Does Not Determine Performance. Toolchain Configuration Does.

Stage 1 showed Zig winning. Stage 2 showed C++ winning — on the **exact same algorithm** — just by adding `-ffast-math`. This should disturb you. A single compiler flag changed the winner. The code didn't change. The algorithm didn't change. Only the instructions we gave the optimizer changed.

The implication: before you benchmark languages, you must ask whether both compilers are operating at equivalent capability levels. Most online "language benchmarks" fail this basic requirement.

### Lesson 2: RAM Is a Flat Line. Stride Is Lethal.

The switch from `(i,j,k)` to `(i,k,j)` produced between **12× and 30× speedups** across all three languages. No flags changed. No algorithms changed. Just the order of three nested loops.

This is the most important optimization insight in this entire project. The physics of your memory system dictates what loop orders are fast. Writing cache-friendly code is not an advanced optimization — it is the baseline requirement for serious systems work.

### Lesson 3: The Compiler Is Smarter Than You (Sometimes)

In Stage 4, we manually implemented cache-blocking/tiling — a technique from the BLAS literature used by libraries like OpenBLAS and Intel MKL. For Rust, it helped (-17%). For C++, it barely mattered (-4%). For Zig, it **hurt badly** (+58% slower).

Why? Because the simple `(i,k,j)` loop we had in Stage 3 was a clean, analyzable pattern that LLVM's auto-vectorizer could recognize. The tiled version added `@min()` bounds checks and extra loop variables that introduced branching complexity. The vectorizer could no longer _prove_ the inner loop was safe to turn into AVX2 instructions, so it backed off to scalar code. We got in the compiler's way.

### Lesson 4: `-ffast-math` Is Not Just a Flag. It Is a Different Contract.

IEEE 754 floating-point mandates a strict order of operations. `(a + b) + c` must equal `a + (b + c)` in defined ways. SIMD vectorization needs to reorder and group these operations. `-ffast-math` relaxes the IEEE 754 contract, giving the compiler permission to restructure floating-point math for throughput. This is what enables AVX2. Without it, you leave ~8× of compute performance on the table.

For scientific computation requiring reproducible floating-point results (weather modeling, financial calculation), you cannot use `-ffast-math`. For everything else — machine learning, signal processing, graphics — it is almost always the right choice.

---

## Build and Replicate

### Prerequisites

- **Zig 0.15.2** — [ziglang.org/download](https://ziglang.org/download)
- **Rust** with `x86_64-pc-windows-gnu` target — `rustup target add x86_64-pc-windows-gnu`
- **G++ 15.2.0** via MSYS2/MinGW64

### Step 1: Build the Rust Static Library

```bash
cd rust
# -C target-cpu=native tells rustc to use your CPU's specific instruction set
RUSTFLAGS="-C target-cpu=native" cargo build --release --target x86_64-pc-windows-gnu
cd ..
```

This produces `rust/target/x86_64-pc-windows-gnu/release/libmatrix_rs.a` — a static archive that Zig will link at compile time.

### Step 2: Build and Run

```bash
# Remove all cached build artifacts (important for accurate timing)
zig build clean

# Zig compiles matrix.cpp, compiles matrix.zig, links libmatrix_rs.a,
# resolves Windows system libraries, and produces bench.exe
zig build run -Doptimize=ReleaseFast -Dtarget=native
```

```bash
you can also export the run_benchmark_stages.sh using chmod and then run ./run_benchmark_stages.sh
note that this eventually runs the stages based on the gittrees for the code at the commit, so if you update the codebase only stage 4 gets updated.
```

### Expected Output

```
=== Matrix Multiplication Benchmark (1024x1024 * 1024x1024) ===
Zig:  1367 ms
Rust: 647 ms
C++:  401 ms
Results match: true
```

---

## Deep Documentation Index

| Document                                       | What It Covers                                                                                                                                                         |
| :--------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[DEEP_DIVE.md](./DEEP_DIVE.md)**             | The physics of RAM, cache lines, stride, SIMD, and why loop order is your most important design decision. Read this to understand _why_ the numbers are what they are. |
| **[PERFORMANCE_LOG.md](./PERFORMANCE_LOG.md)** | The full, auditable changelog: every code change, every flag added, every result measured. Read this to follow the investigation step by step.                         |

---

## What Comes Next (Future Stages)

The journey doesn't end at Stage 4. Here is the roadmap for further investigation:

- **Stage 5: Assembly Inspection** — Use `zig build-exe -femit-asm` and `objdump` to look at the actual x86 instructions generated. Confirm whether AVX2 YMM registers are being used. Count the unroll factor.
- **Stage 6: Explicit SIMD Intrinsics** — Manually write AVX2 intrinsic calls (`_mm256_fmadd_ps`) to eliminate all ambiguity and see how close we can get to theoretical peak FLOPs.
- **Stage 7: Multi-threaded Parallelism** — Add `std.Thread` (Zig) and `rayon` (Rust) to distribute the outer loop across CPU cores. On a 4-core machine, the theoretical ceiling is 4× improvement.
- **Stage 8: Python/Go/TypeScript FFI** — Compile this library as a shared `.dll`/`.so` and call it from Python (`ctypes`), Go (`cgo`), and Node.js (`node-ffi-napi`) to demonstrate the full production integration story.

---

## Project Structure

```
matrix-lib/
├── build.zig              # Zig build system — compiles everything
├── README.md              # This file — the narrative
├── DEEP_DIVE.md           # The physics and mathematics of the optimization
├── PERFORMANCE_LOG.md     # Auditable benchmark history
│
├── bench/
│   └── bench.zig          # The benchmark harness (calls all three implementations)
│
├── zig/
│   └── matrix.zig         # Zig implementation (exports C ABI)
│
├── cpp/
│   ├── matrix.h           # C header (extern "C" wrapper)
│   └── matrix.cpp         # C++ implementation (class-based, C-exported)
│
└── rust/
    ├── Cargo.toml         # Rust package config (staticlib, LTO, panic=abort)
    └── src/
        ├── lib.rs         # Crate root
        └── matrix.rs      # Rust implementation (unsafe raw pointers, C ABI)
```

## 🧠 Benchmark Variance & Cache Effects (Important Insight)

During repeated benchmarking runs, performance results vary significantly even when the code and inputs remain unchanged.

Example observed results:

Zig: 748 ms → 158 ms → 178 ms → 164 ms → 176 ms  
Rust: 719 ms → 174 ms → 186 ms → 211 ms → 234 ms  
C++: 367 ms → 152 ms → 170 ms → 182 ms

### Why this happens

Matrix multiplication performance is heavily influenced by **CPU state**, not just code:

- **Cache warmth (L1/L2/L3):**  
  Data may already be cached from previous runs, making execution significantly faster.
- **Cache eviction:**  
  Background processes (browser, OS services) can evict hot data from cache, causing slowdowns.
- **Branch predictor & prefetcher state:**  
  Modern CPUs “learn” memory access patterns over time, improving or degrading performance between runs.
- **OS scheduling noise:**  
  CPU time is shared with system processes, introducing variability.

---

### Key Insight

> Performance is not just about computation speed — it is about **memory locality and CPU cache reuse**.

Matrix multiplication performance is dominated by:

- How efficiently data fits into cache lines (typically 64 bytes)
- Whether memory access is sequential or strided
- How often the CPU must fetch from L2/L3 or RAM

---

### Practical Conclusion

Small code changes may not matter as much as:

- Memory access patterns
- Cache reuse efficiency
- Data layout in memory

In high-performance systems, the goal is:

> **Minimize cache misses and maximize reuse per cache line fetched.**

---

### Implication for this project

This benchmark demonstrates that:

- Language choice alone is not the primary performance factor
- Compiler optimizations and memory access patterns dominate runtime behavior
- Real-world performance must be measured across multiple runs, not single executions

---

_Built on an i5-6300U in Juja, Kenya. Proof that world-class systems engineering doesn't require a FAANG badge — just the willingness to read what the hardware is trying to tell you._

