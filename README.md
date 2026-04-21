# matrix-lib: A Polyglot Systems Performance Journey

> _"In systems engineering, we don't just write code that works. We write code that vibrates with the hardware."_
> *"Hardware changes. Physics doesn't."*
> — from the project's first cross-platform PR

---

```text
╔══════════════════════════════════════════════════════════════════════╗
║                    THE POLYGLOT ENGINE                               ║
║                                                                      ║
║   Your Application Code (Python / Go / TypeScript / Node.js)        ║
║          │                                                           ║
║          ▼                                                           ║
║   ┌──────────────────────────────────────────┐                      ║
║   │         C  A B I  B o u n d a r y        │  ← Zero-overhead     ║
║   └──────────────────────────────────────────┘     FFI calls        ║
║          │               │               │                          ║
║          ▼               ▼               ▼                          ║
║      ┌───────┐       ┌───────┐       ┌───────┐                      ║
║      │  Zig  │       │ Rust  │       │  C++  │  ← Compute Kernels   ║
║      └───────┘       └───────┘       └───────┘                      ║
║          │               │               │                          ║
║          └───────────────┼───────────────┘                          ║
║                          ▼                                           ║
║          ┌────────────────────────────────┐                         ║
║          │   Zig Build System (build.zig) │  ← Unified Orchestrator ║
║          │   Compiles C++, links Rust     │                         ║
║          │   .a staticlib, resolves all   │                         ║
║          │   platform system deps         │                         ║
║          └────────────────────────────────┘                         ║
╚══════════════════════════════════════════════════════════════════════╝
```

---

## What This Repository Is

This is not a typical "language comparison" project. Those are almost always misleading — they benchmark toy problems with inconsistent flags and declare a winner before the conversation even starts.

This is a **recorded, auditable, cross-platform investigation** into what actually governs performance in low-level systems code. We used matrix multiplication as the probe, but the real subject under study is the relationship between your source code, the compiler's optimizer, and the CPU's memory subsystem.

We ran five optimization stages on two completely different CPU architectures:
- An **Intel Core i5-6300U** (Skylake, x86_64, 2015 laptop chip, Windows/MSYS2)
- An **Apple M3** (ARM64, 2024, macOS, `aarch64-apple-darwin`) — contributed via an automated cross-platform PR

The M3 is approximately **10× faster** in absolute terms. But every single pattern we observed — the massive speedup from loop reordering, the regression from tiling in Zig, Rust's improvement from tiling — reproduced on both machines.

That reproducibility is the point. **The physics of cache lines does not care what year your chip was manufactured or what instruction set it speaks.**

---

## The Core Finding — In One Table

1024×1024 × 1024×1024 matrix multiplication (~2.1 billion FLOPs):

| Stage | Algorithm | i5-6300U Zig | i5-6300U Rust | i5-6300U C++ | M3 Zig | M3 Rust | M3 C++ |
|:---|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **1** | Naive `(i,j,k)` | 10,414ms | 12,826ms | 12,820ms | 1,020ms | 1,081ms | 1,284ms |
| **2** | Flags standardized | 13,466ms | 12,685ms | 10,671ms | 1,026ms | 1,084ms | 1,263ms |
| **3** | Loop flip `(i,k,j)` | 865ms | 785ms | 419ms | 89ms | 83ms | 83ms |
| **4** | 64×64 tiling | 1,367ms | 647ms | 401ms | 144ms | 126ms | 119ms |
| **5** | **Hierarchical funnel + SIMD µ-kernel** | **135ms** | **135ms** | **152ms** | *pending* | *pending* | *pending* |

**Read Stage 5 carefully.** All three languages converged to within 12% of each other — 135ms for Zig and Rust, 152ms for C++. This is a **77–95× speedup from Stage 1** achieved through five incremental changes: access pattern (12×), cache blocking (2×), hierarchical tiling (3×), and explicit SIMD micro-kernels (3×). The hierarchy compounds.

---

## Cross-Architecture Analysis — What the M3 Data Reveals

### Finding 1: Stage 3 Converges All Three Languages on M3

On the i5-6300U, Stage 3 produced a clear ranking: C++ at 419ms, Rust at 785ms, Zig at 865ms. A **2× gap** between the fastest and slowest.

On the M3, Stage 3 produced: Rust 83ms, C++ 83ms, Zig 89ms. All within **7% of each other**.

The language gap collapsed entirely on newer hardware. Why? The M3 has a far more powerful out-of-order execution engine and a more aggressive hardware prefetcher than Skylake. Once the stride-access pattern was eliminated (removing the cache miss storm), all three compilers generated code that the M3's backend could execute with near-equal efficiency — the microarchitecture was good enough to smooth out whatever remaining code quality differences existed between them.

**The systems engineering implication**: Code that looks equivalent across languages on a modern M3 may show a 2× difference on older server hardware. **Always benchmark on your weakest target machine, not your fastest development machine.**

### Finding 2: The Zig Stage 4 Regression Is Architecture-Independent

On the i5-6300U: Zig went from 865ms → 1,367ms — a **+58% regression**.
On the M3: Zig went from 89ms → 144ms — a **+62% regression**.

Nearly the same regression magnitude on a completely different CPU, OS, and toolchain invocation. This confirms the regression lives in the **compiler's optimizer**, not in hardware behavior. LLVM's auto-vectorizer, when presented with the tiled Zig code's `@min()` boundaries and `while` loop structure, backs off from vectorization. That decision is made by LLVM's analysis passes before it even knows what CPU backend it's targeting.

**A compiler behavior is more portable than hardware behavior.** If LLVM fails to vectorize your code on your laptop, it will probably fail on your server too.

### Finding 3: Absolute Numbers Are Hardware-Specific. Ratios Are Not.

M3 Stage 3: ~83–89ms. i5-6300U Stage 3: ~419–865ms. The absolute gap is ~10×.

But the *ratio* between stages is stable:
- i5: Stage 1 → Stage 3 speedup = ~13× (Zig), ~16× (Rust), ~30× (C++)
- M3: Stage 1 → Stage 3 speedup = ~11× (Zig), ~13× (Rust), ~15× (C++)

The ratios are in the same ballpark across a decade of hardware evolution. This means: **if you observe a 10× speedup from a cache-friendly access pattern on your development machine, you can reasonably expect a similar-magnitude speedup on your deployment hardware.** The absolute times will differ. The pattern will not.

---

## Automated Stage Runner

A contributor ([@million-in](https://github.com/million-in)) added `run_benchmark_stages.sh` — a shell script that uses `git worktree` to check out each historical stage commit, copies stage-matched kernels for all three languages, and runs the benchmark. Each stage has immutable kernel snapshots (`zig/matrix_stage{1..5}.zig`, `cpp/matrix_stage{1..5}.cpp`, `rust/src/matrix_stage{1..5}.rs`) ensuring reproducibility regardless of the current working tree state.

```bash
# Clone the repo
git clone https://github.com/Mwangi-Derrick/matrix-interop-demo
cd matrix-interop-demo

# Run all four stages automatically — no manual git checkout required
chmod +x run_benchmark_stages.sh
./run_benchmark_stages.sh
```

The script detects the host target:
- `x86_64-pc-windows-gnu` on Windows/MSYS2
- `aarch64-apple-darwin` on Apple Silicon
- `x86_64-apple-darwin` on Intel Mac
- `x86_64-unknown-linux-gnu` on Linux

**Why this matters**: Without automated reproducibility, benchmark data is anecdote. With it, any engineer who clones this repository can re-derive every number in this documentation from scratch in under ten minutes. The data is falsifiable. That is what distinguishes an engineering artifact from a blog post.

---

## The Lessons (Cross-Platform Validated)

### Lesson 1: Memory Access Pattern Is the Dominant Factor

Loop reordering produced 12–30× speedup on x86_64 and 11–15× on ARM64. Compiler flags across the same algorithm produced less than 2× on either. The physics of sequential vs. stride memory access is not architecture-specific — it is a consequence of how every cache hierarchy works, from Skylake to M3 to whatever comes next.

### Lesson 2: Language Convergence Scales With CPU Quality

On the i5-6300U, C++ was 2× faster than Zig in Stage 3. On the M3, all three were within 7%. Better hardware can mask compiler quality differences. **Benchmark on your weakest target.**

### Lesson 3: Compiler Behavior Is More Portable Than You Think

The Zig Stage 4 regression reproduced at ~60% magnitude on both x86_64 and ARM64. LLVM's vectorization decisions are made by the optimizer before the backend. A vectorization failure on your laptop is a vectorization failure on your server.

### Lesson 4: Automated Reproducibility Is Not Optional

If your benchmark data cannot be reproduced by a stranger on their own machine, it is not data. The `run_benchmark_stages.sh` script is as important to this project as the code itself.

### Lesson 5: `-ffast-math` Is Architecture-Significant, Not Cosmetic

Stage 2 added `-ffast-math` to C++ and saw a ~17% improvement on i5 but barely 2% on M3. On M3, Stage 3's access pattern change alone delivered the same improvement. The flag matters — but its impact depends on how compute-bound or memory-bound your code already is. On the memory-bound naive implementation, relaxing IEEE 754 couldn't help much because the CPU was waiting on RAM, not computing. On Stage 3's sequential access pattern, the flag unlocked AVX2 vectorization on x86_64 but mattered less on M3 where the out-of-order engine already compensated.

---

## Build and Replicate

### Automated (Recommended)
```bash
./run_benchmark_stages.sh
```

### Manual Build

**Windows (MSYS2/MinGW64):**
```bash
cd rust
RUSTFLAGS="-C target-cpu=native" cargo build --release --target x86_64-pc-windows-gnu
cd ..
zig build clean
zig build run -Doptimize=ReleaseFast -Dtarget=native
```

**macOS (Apple Silicon):**
```bash
cd rust
RUSTFLAGS="-C target-cpu=native" cargo build --release --target aarch64-apple-darwin
cd ..
zig build clean
zig build run -Doptimize=ReleaseFast -Dtarget=native
```

**Linux:**
```bash
cd rust
RUSTFLAGS="-C target-cpu=native" cargo build --release --target x86_64-unknown-linux-gnu
cd ..
zig build clean
zig build run -Doptimize=ReleaseFast -Dtarget=native
```

---

## Project Structure

```
matrix-lib/
├── build.zig                  # Zig build system — compiles & links everything
├── run_benchmark_stages.sh    # Automated multi-stage benchmark runner (all platforms)
├── Justfile                   # Task runner shortcuts
├── README.md                  # This file
├── DEEP_DIVE.md               # Physics of RAM, cache lines, SIMD, loop order
├── PERFORMANCE_LOG.md         # Full auditable benchmark history — both architectures
│
├── bench/
│   ├── bench.zig              # Benchmark harness (calls all three implementations)
│   ├── cache_info.zig         # Cache detection dispatch (OS-specific)
│   └── cache/
│       ├── common.zig         # Block size calculation (cache utilization %)
│       ├── windows.zig        # Windows cache detection (GetLogicalProcessorInformation)
│       ├── linux.zig          # Linux cache detection (/sys/devices/system/cpu/)
│       └── macos.zig          # macOS cache detection (sysctlbyname)
│
├── zig/
│   ├── matrix.zig             # Active Zig kernel (= Stage 5)
│   ├── matrix_stage1.zig      # Stage 1: Naive (i,j,k)
│   ├── matrix_stage2.zig      # Stage 2: Same algorithm, flags differ
│   ├── matrix_stage3.zig      # Stage 3: Loop flip (i,k,j)
│   ├── matrix_stage4.zig      # Stage 4: Single-level 64×64 tiling
│   └── matrix_stage5.zig      # Stage 5: Hierarchical funnel + SIMD µ-kernel
│
├── cpp/
│   ├── matrix.h               # C header (extern "C" wrapper)
│   ├── matrix.cpp             # Active C++ kernel (= Stage 5)
│   ├── matrix_stage1.cpp      # Stage 1: Naive (i,j,k)
│   ├── matrix_stage2.cpp      # Stage 2: Same algorithm, flags differ
│   ├── matrix_stage3.cpp      # Stage 3: Loop flip (i,k,j)
│   ├── matrix_stage4.cpp      # Stage 4: Single-level tiling
│   └── matrix_stage5.cpp      # Stage 5: Hierarchical funnel + SIMD µ-kernel
│
└── rust/
    ├── Cargo.toml             # staticlib, LTO=fat, panic=abort
    └── src/
        ├── lib.rs
        ├── matrix.rs           # Active Rust kernel (= Stage 5)
        ├── matrix_stage1.rs    # Stage 1: Naive (i,j,k) with safe slices
        ├── matrix_stage2.rs    # Stage 2: Same algorithm, RUSTFLAGS differ
        ├── matrix_stage3.rs    # Stage 3: Loop flip + raw pointers
        ├── matrix_stage4.rs    # Stage 4: Single-level tiling
        └── matrix_stage5.rs    # Stage 5: Hierarchical funnel + SIMD µ-kernel
```

---

## Deep Documentation

| Document | What It Covers |
|:---|:---|
| **[DEEP_DIVE.md](./DEEP_DIVE.md)** | The physics of RAM, cache lines, stride, SIMD, and why loop order is your most important design decision. Includes address-level memory traces, SIMD register analysis, and the register micro-kernel architecture. |
| **[PERFORMANCE_LOG.md](./PERFORMANCE_LOG.md)** | Every stage: exact code, exact flags, measured results on both i5-6300U and Apple M3. The full auditable record with 77–95× speedup documented step by step. |

---

## Roadmap

| Stage | Status | Description |
|:---|:---:|:---|
| 1 — Naive baseline | ✅ | Standard `(i,j,k)`, default flags |
| 2 — Toolchain normalization | ✅ | `-march=native -ffast-math` standardized |
| 3 — Loop flip `(i,k,j)` | ✅ | Hardware-sympathetic access pattern |
| 4 — Cache-blocked tiling | ✅ | 64×64 block structure |
| 5 — Hierarchical funnel + SIMD µ-kernel | ✅ | 3-level cache funnel, 4×4 register micro-kernel, explicit SIMD |
| 6 — Matrix packing | 🔲 | Contiguous tile buffers, TLB miss elimination |
| 7 — Multithreaded GEMM | 🔲 | `std.Thread` / `rayon` outer-loop parallelism |
| 8 — FFI integration | 🔲 | Python `ctypes`, Go `cgo`, Node `ffi-napi` demos |

---

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
*Built on an i5-6300U in Juja, Kenya. Validated on an M3 MacBook. The hardware was different. The physics was identical.*

*Best result: 135ms on the i5 for 2.1 billion FLOPs — a 77× improvement from the naive baseline, achieved through five incremental, documented, reproducible steps.*