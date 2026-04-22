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

1024×1024 × 1024×1024 matrix multiplication (~2.1 billion FLOPs).
Results from `run_benchmark_stages.sh` — median of 5 runs, all stages reproducible:

| Stage | Algorithm | i5-6300U | CI Win x64 | macOS Intel | macOS ARM64 | Linux x64 | Linux ARM64 |
|:---|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **1** | Naive `(i,j,k)` | 8,153ms | 5,656ms | 2,193ms | 2,107ms | 3,634ms | 1,302ms |
| **2** | Flags standardized | 10,187ms | 5,500ms | 2,444ms | 2,070ms | 3,783ms | 1,320ms |
| **3** | Loop flip `(i,k,j)` | 245ms | **62ms** | 164ms | 121ms | 147ms | 117ms |
| **4** | Dynamic L1 tiling | 207ms | 163ms | 231ms | 163ms | 122ms | 157ms |
| **5** | **Hierarchical + SIMD µ-kernel** | **141ms** | 196ms | **109ms** | **122ms** | **77ms** | **117ms** |

*Numbers show best language per stage. Full per-language breakdown in [PERFORMANCE_LOG.md](PERFORMANCE_LOG.md).*

**Stage 5 wins on 5 of 6 machines.** The one exception (CI Windows, 32 MB L3) has a cache large enough to hold the entire working set, making tiling overhead counterproductive. On every machine where cache blocking matters, the hierarchical funnel + SIMD architecture is the fastest.

---

## Cross-Architecture Analysis — Six Machines, One Physics

### Finding 1: Stage 3 Is the Big Win Everywhere

The loop flip (i,j,k → i,k,j) is the single largest optimization: **15–40× speedup** across all 6 machines. Cache line physics is universal — sequential access beats strided access on every cache hierarchy ever built.

### Finding 2: Stage 4 Tiling — Not Always Better

On machines with small L3 caches (i5-6300U: 3MB, macOS ARM: 3MB SLC), Stage 4's dynamic tiling helps: 245ms → 207ms on the i5. But on machines with massive L3s (CI Windows: 32MB, Linux x64: 48MB), the full working set (~12MB for 1024² matrices) fits in cache — tiling adds loop overhead for zero benefit. **Stage 3 beats Stage 4 on large-cache machines.** This is not a bug; it's physics.

### Finding 3: Stage 5 Proves Its Architecture on Real Machines

The hierarchical funnel (L3 → L2 → L1 → registers) with a 4×4 SIMD micro-kernel was *previously* measured as slower than Stage 4 due to **thermal throttling** on the i5-6300U (15W TDP, clocks drop from 3.0→1.6 GHz during sustained benchmarks). After adding 5-second cooldown pauses between stages, Stage 5 is clearly the winner: 141ms vs 207ms — a **32% improvement** over Stage 4.

### Finding 4: C++ Is Consistently Fastest in Stage 5

Across all 6 machines, C++ Stage 5 produces the best times (109ms macOS Intel, 77ms Linux x64, 117ms Linux ARM64). The `__restrict` qualifier + explicit vector types give Clang maximum optimization freedom.

### Finding 5: Rust Has a NEON Bug

On Linux ARM64 (Graviton), Rust Stage 5 is **373ms** vs Zig 123ms and C++ 117ms — a 3× regression. The Rust compiler's aliasing analysis fails to NEON-vectorize the raw-pointer micro-kernel on aarch64. Zig and C++ (both using Clang directly) don't have this issue.

---

## Automated Stage Runner

`run_benchmark_stages.sh` uses `git worktree` + immutable stage-matched kernels (`zig/matrix_stage{1..5}.zig`, `cpp/matrix_stage{1..5}.cpp`, `rust/src/matrix_stage{1..5}.rs`) to reproduce every number in this document. Thermal cooldown between stages on local machines prevents throttling bias.

```bash
git clone https://github.com/Mwangi-Derrick/matrix-interop-demo
cd matrix-interop-demo
chmod +x run_benchmark_stages.sh
./run_benchmark_stages.sh
```

Tested on 6 platforms via CI: Windows x64, macOS Intel, macOS ARM64, Linux x64, Linux ARM64, and locally on the i5-6300U.

---

## The Lessons (Cross-Platform Validated, 6 Machines)

### Lesson 1: Memory Access Pattern Is the Dominant Factor

Loop reordering produced 15–40× speedup across x86_64 and ARM64. Compiler flags across the same algorithm produced less than 2×. The physics of sequential vs. stride memory access is not architecture-specific — it is a consequence of how every cache hierarchy works.

### Lesson 2: Block Size Correctness Matters More Than Block Existence

The original Stage 4 used a hardcoded `BLOCK_SIZE=64`, which overflows the 32KB L1 (64²×3×4 = 49KB > 32KB). Dynamically calculated `l1_block=48` (27KB < 32KB) fixed a phantom "regression" that wasn't a regression at all — it was a misconfigured parameter.

### Lesson 3: Thermal Throttling Corrupts Benchmark Data

On the i5-6300U (15W TDP), running stages 1-2 (~7 minutes of sustained compute) caused Stage 5 to measure 274ms instead of 153ms — a **1.8× error** from thermal throttling alone. Adding 5-second cooldown pauses between stages recovered accurate measurements. CI runners with active cooling don't have this issue.

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
*Built on an i5-6300U in Juja, Kenya. Validated on 6 machines across 4 operating systems and 2 architectures. The hardware was different. The physics was identical.*

*Best result: 77ms (C++ Stage 5, Linux x64) — a 49× improvement from the naive baseline, achieved through five documented, reproducible steps.*