# DEEP_DIVE.md — Touching the Metal: A Systems Engineering Masterclass

> *"The gap between a working program and a fast program is the gap between a programmer who models the algorithm and a programmer who models the machine."*

This document will fundamentally change how you think about loops, memory, and compilers. We work from first principles — starting at the physics of how RAM is organized and building up to SIMD vector instructions and compiler behavior across two CPU architectures. Every claim is grounded in benchmark data from this project.

Read this slowly. Challenge every claim. Re-read the code snippets until you can predict what the CPU is doing on each iteration. That is the goal.

---

## Part 1: The Lie Your Language Tells You

### 1.1 — What a Matrix "Is" in Your Mind vs. in RAM

When a mathematician writes a 3×3 matrix:

```
    Col 0   Col 1   Col 2
Row 0 [ 1,     2,     3  ]
Row 1 [ 4,     5,     6  ]
Row 2 [ 7,     8,     9  ]
```

This is a conceptual model. It describes relationships between numbers. The math is clean, grid-like, elegant.

Now ask yourself a harder question: **how does the RAM chip inside your laptop physically store this?**

RAM — Dynamic Random-Access Memory — is organized as a one-dimensional array of memory cells. Each cell is an address. Each address holds bytes. There are no "rows" or "columns" in RAM. There is only a linear sequence of addresses from `0x0000000000000000` upward to the highest address your CPU can address..

When Zig, Rust, or C++ allocates a 3×3 matrix of `f32` (4-byte floats), the compiler **flattens** it into **Row-Major Order**:

```
Physical RAM (each slot = 4 bytes = one f32):

Address: 0x000  0x004  0x008  0x00C  0x010  0x014  0x018  0x01C  0x020
Value:   [  1,     2,     3,     4,     5,     6,     7,     8,     9  ]
         ├── Row 0 ──────────┤├── Row 1 ──────────┤├── Row 2 ──────────┤
```

Row 0 is stored first: `1, 2, 3`. Then Row 1: `4, 5, 6`. Then Row 2: `7, 8, 9`. The rows are **contiguous** — packed next to each other in address space.

This is Row-Major Order. It is the default in C, C++, Rust, Zig, and most systems languages. (Fortran and some numerical libraries use Column-Major. NumPy lets you choose. This distinction will matter enormously.)

**The critical implication**: if you want to walk down **Column 0** (values `1, 4, 7`), you have to jump:
- `1` is at address `0x000`
- `4` is at address `0x00C` — a jump of 12 bytes (3 floats × 4 bytes)
- `7` is at address `0x018` — another jump of 12 bytes

For our 1024×1024 matrix, a column jump is not 12 bytes. It is **4,096 bytes** (1024 floats × 4 bytes/float). Every step down a column requires a 4 KB stride across memory.

This number — 4,096 bytes — is where all our trouble starts.

---

### 1.2 — The Memory Hierarchy: Why RAM Access Takes Forever

Here is something that surprises most programmers: your CPU can execute an arithmetic operation (addition, multiplication) in about **1 clock cycle**. At 2.4 GHz, that's 0.4 nanoseconds.

Accessing a value from RAM, on the other hand, takes **~100 clock cycles**. That's 40 nanoseconds of waiting.

The CPU is ~100× faster at computing than at fetching data from RAM. If your code constantly needs data from RAM, the CPU spends 99% of its time waiting. That is exactly what we measured in Stage 1 — ~13,000 milliseconds for a computation that takes ~400 milliseconds once the data access pattern is fixed.

To bridge this gap, CPU architects added a **cache hierarchy** — multiple layers of increasingly fast (and increasingly small) storage between the cores and main RAM:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Storage Layer    │  i5-6300U (Skylake) │  Apple M3           │  Latency    │
├───────────────────┼─────────────────────┼─────────────────────┼─────────────┤
│  CPU Registers    │  ~1 KB per core     │  ~1 KB per core     │  0 cycles   │
│  L1 Data Cache    │  64 KB per core     │  128 KB per cluster │  ~4 cycles  │
│  L2 Cache         │  256 KB per core    │  4 MB per cluster   │  ~12 cycles │
│  L3 Cache (LLC)   │  3 MB shared        │  ~12–24 MB shared   │  ~30 cycles │
│  RAM (DRAM)       │  varies             │  varies             │  ~100 cycles│
└─────────────────────────────────────────────────────────────────────────────┘
```

Notice the M3's dramatically larger caches. This is a significant part of why the M3 achieves ~10× better absolute performance on this benchmark — for some matrix sizes, the M3's L3 cache is large enough to contain the entire working set that the i5's L3 cannot hold.

The cache hierarchy works because of two principles: **temporal locality** (recently accessed data will likely be accessed again) and **spatial locality** (data near recently accessed data will likely be accessed soon). Both caches exploit these patterns — but only if your code's access pattern cooperates.

---

### 1.3 — The Cache Line: The Atomic Unit of Memory Currency

A Cache Line is the smallest unit of data that the CPU can transfer between RAM and the L1 cache. On virtually all modern x86 and ARM processors (including both the Skylake i5 and the M3), a cache line is **64 bytes**.

Since our floats are 4 bytes each, one cache line holds **16 floats**.

When your code accesses a value at address `0x000`, the CPU doesn't fetch just that float. It fetches the entire 64-byte cache line — the float at `0x000` **plus the 15 floats immediately following it**.

This is free. Fetching 16 adjacent floats costs the same RAM round-trip as fetching 1.

The hardware's implicit bet: *if you need the float at address X, you will probably need the float at X+4 very soon.* The cache line is the hardware's built-in spatial locality optimization.

**When this bet pays off** (sequential access): every cache line you fetch gives you 15 free future accesses. You use all 16 floats. Cache efficiency = 100%.

**When this bet fails** (stride access): you fetch 16 floats, use 1, and jump 4,096 bytes to the next value. The other 15 floats are evicted before you ever need them. Cache efficiency ≈ 6%.

That difference — 100% vs. 6% cache efficiency — is where our 48× speedup was hiding. The CPU was doing the right thing. Our code was fighting it.

---

## Part 2: The Naive Loop Autopsy

### 2.1 — The Algorithm We Started With

Matrix multiplication $C = A \times B$ where $A$ is $m \times n$ and $B$ is $n \times p$ and $C$ is $m \times p$ is defined mathematically as:

$$C[i][j] = \sum_{k=0}^{n-1} A[i][k] \times B[k][j]$$

For every cell `(i, j)` in the result, you sum `n` products across a row of A and a column of B.

Transcribed directly into code, this gives us the canonical triple loop:

```zig
// zig/matrix.zig — Stage 1: Naive (i, j, k) order
export fn zig_matrix_multiply(
    a_ptr: [*]f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]f32, _b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void {
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;

    for (0..m) |i| {           // outer: rows of A and Result
        for (0..p) |j| {       // middle: columns of B and Result
            var sum: f32 = 0.0;
            for (0..n) |k| {   // inner: the dot product accumulator
                sum += a_ptr[i * n + k] * b_ptr[k * p + j];
                //                        ^^^^^^^^^^^^^^^^
                //                        This accesses B by COLUMN.
                //                        B[0][j], B[1][j], B[2][j]...
                //                        Each step is a 4,096-byte jump in RAM.
            }
            result_ptr[i * p + j] = sum;
        }
    }
}
```

This is correct. It matches the formula exactly. And for 1024×1024, it runs in ~10,000–13,000 milliseconds. Let's understand exactly why.

### 2.2 — Tracing the Cache Behavior Step by Step

Freeze the outer two loops. Set `i=0, j=0`. Trace the innermost `k` loop:

```
k=0:  A[0,0] addr=0x000_0000  → A's cache line loaded: [A[0,0]..A[0,15]] ✓
      B[0,0] addr=0x000_0000  → B's cache line loaded: [B[0,0]..B[0,15]] ✓

k=1:  A[0,1] addr=0x000_0004  → already in L1 from k=0 ✓
      B[1,0] addr=0x000_1000  → 4,096 bytes away. NOT in cache. RAM FETCH. ✗
      CPU stalls ~100 cycles waiting for RAM.

k=2:  A[0,2] addr=0x000_0008  → already in L1 ✓
      B[2,0] addr=0x000_2000  → another 4,096 byte jump. RAM FETCH. ✗
      CPU stalls ~100 cycles.

k=3:  A[0,3] addr=0x000_000C  → already in L1 ✓
      B[3,0] addr=0x000_3000  → RAM FETCH. ✗
      ...

k=1023: B[1023,0] addr=0x000_FF000 → RAM FETCH. ✗
```

**Every iteration of the k loop is a cache miss on Matrix B.**

When the L1 cache fills up (32 KB = ~8,192 floats), it starts evicting old cache lines to make room for new ones. Matrix B is 1024×1024 = 4,194,304 floats = 16 MB. The L3 cache is 3 MB. Matrix B **does not fit in any cache**. Every column access is a guaranteed RAM fetch.

Each cache miss = ~100 stall cycles. For one cell of the result (`i=0, j=0`), we execute 1024 iterations of k = **1,024 cache misses**. For all 1024×1024 cells = **~1 billion cache misses**.

At 100 cycles per miss at 2.4 GHz: `10^9 × 100 / 2.4×10^9 ≈ 42 seconds` of waiting. We measured ~13 seconds — shorter because hardware has partial mitigations (out-of-order execution, hardware prefetching patterns that occasionally help), but the bottleneck is clear.

The CPU's arithmetic units sat idle for ~95% of the runtime, waiting for RAM to deliver the next element of Matrix B.

### 2.3 — Why Zig Led in Stage 1 Despite the Same Cache Behavior

Stage 1 results: Zig 10,414ms, C++ 12,820ms, Rust 12,826ms. Same algorithm. Same cache pattern. Why a 20% gap?

The answer is **default optimization profiles**:

**Zig `ReleaseFast`** enables something equivalent to `-ffast-math` by default, plus aggressive inlining and aliasing relaxations. Even on the cache-miss-heavy naive loop, LLVM can apply limited FP reassociation that reduces some overhead.

**C++ with `-O3` (without `-march=native`)** targets generic x86-64, staying within SSE2 (128-bit SIMD, 4 floats at once). No AVX2 (256-bit, 8 floats).

**Rust `--release` (without `target-cpu=native`)** same issue — generic x86-64 baseline, no AVX2.

This is the Stage 1 lesson: **compiler defaults are not equal**. Zig's out-of-box settings happened to be more aggressive. That is not evidence that Zig is faster — it is evidence that comparing languages without normalizing flags is meaningless.

---

## Part 3: The Loop Flip — Hardware Sympathy in Action

### 3.1 — The Fix: Make the Innermost Loop Walk Forward Through Memory

The naive `(i, j, k)` order has `k` in the innermost position, which makes it stride across columns of B. The fix is to move `j` to the innermost position so it strides across rows — the natural direction of memory.

```zig
// zig/matrix.zig — Stage 3: Cache-Aware (i, k, j) order
export fn zig_matrix_multiply(
    a_ptr: [*]const f32, a_rows: usize, a_cols: usize,
    b_ptr: [*]const f32, _b_rows: usize, b_cols: usize,
    result_ptr: [*]f32
) void {
    _ = _b_rows;
    const m = a_rows;
    const n = a_cols;
    const p = b_cols;

    @memset(result_ptr[0 .. m * p], 0); // Zero first — we accumulate now

    for (0..m) |i| {
        for (0..n) |k| {                    // k moved to middle
            const a_val = a_ptr[i * n + k]; // Loaded ONCE, held in a register
            for (0..p) |j| {                // j moved to innermost
                //
                // result_ptr[i * p + j]: sequential access ✓
                // b_ptr[k * p + j]:      sequential access ✓
                // a_val:                 in a CPU register, no memory access ✓
                //
                result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
            }
        }
    }
}
```

**Is this mathematically identical?** Yes. Matrix multiplication is a sum of products. The order we accumulate those products in does not change the final sum (modulo floating-point rounding, which our correctness check tolerates with a 0.001 threshold). We had to pre-zero the result matrix because we now accumulate into it across multiple k-iterations rather than initializing `sum` fresh for each `(i,j)` cell.

### 3.2 — Tracing the New Cache Behavior

Same analysis, but now freeze `i=0, k=0`, trace the innermost `j` loop:

```
a_val = A[0,0] → loaded ONCE into a register. Cost: 1 cache line load. Done.

j=0:  result[0,0] addr=0x0000  → load/store sequential ✓
      B[0,0]      addr=0x0000  → fetches [B[0,0]..B[0,15]] into L1 ✓

j=1:  result[0,1] addr=0x0004  → in L1 (same line as j=0) ✓
      B[0,1]      addr=0x0004  → in L1 (same line fetched at j=0) ✓

j=2:  result[0,2] → in L1 ✓   B[0,2] → in L1 ✓
j=3:  result[0,3] → in L1 ✓   B[0,3] → in L1 ✓
...
j=15: result[0,15]→ in L1 ✓   B[0,15]→ in L1 ✓ (still same line from j=0)

j=16: result[0,16] → NEW cache line. But hardware prefetcher already fetched it. ✓
      B[0,16]      → NEW cache line. Prefetcher already fetched it. ✓

j=17...j=31: in L1 ✓ (prefetched line)
j=32: Prefetcher fetched the next line. ✓
...
```

**Zero cache misses in the steady state.** The hardware prefetcher sees you scanning forward through memory and fetches the next cache line before you ask. You are using all 16 floats from every cache line you load. Efficiency = 100%.

The RAM traffic comparison:
| Loop Order | Pattern for Matrix B | Cache Lines Fetched |
|:---|:---|:---|
| `(i, j, k)` | One column element per inner iter | ~1 billion fetches |
| `(i, k, j)` | Entire row per k-iter, sequential | ~67 million fetches |

**15× reduction in memory traffic** from rearranging the loop order. The rest of the speedup came from the hardware prefetcher running at full speed and — critically — from the compiler now being able to vectorize the simple sequential inner loop with SIMD instructions.

### 3.3 — Results: Stage 3

```
Intel i5-6300U:
  Zig:  865ms   (was 10,414ms — 12× improvement)
  Rust: 785ms   (was 12,826ms — 16× improvement)
  C++:  419ms   (was 12,820ms — 30× improvement)

Apple M3:
  Zig:   89ms   (was 1,020ms — 11× improvement)
  Rust:  83ms   (was 1,081ms — 13× improvement)
  C++:   83ms   (was 1,284ms — 15× improvement)
```

Notice what happened on the M3: all three languages converged to within 7% of each other. The C++ advantage visible on the i5 (2× faster than Zig) essentially disappeared. The M3's deeper out-of-order execution window and larger caches smoothed out whatever code quality differences remained after the access pattern was fixed. More on this in Part 5.

---

## Part 4: SIMD — When the CPU Does Math in Packs

### 4.1 — What SIMD Actually Is

SIMD — **Single Instruction, Multiple Data** — is a class of CPU instructions that operate on multiple values simultaneously using wide registers.

Normal 64-bit registers hold one float. Vector registers are much wider:

| Register Family | Architecture | Width | Float Capacity |
|:---|:---|:---|:---|
| SSE2 (`xmm0`–`xmm15`) | x86-64 | 128 bits | 4 × f32 |
| AVX/AVX2 (`ymm0`–`ymm15`) | x86-64 Haswell+ | 256 bits | 8 × f32 |
| Neon/ASIMD (`v0`–`v31`) | ARM64 | 128 bits | 4 × f32 |
| SVE | ARM64 (Apple M-series) | 128–2048 bits | variable |

The i5-6300U (Skylake) supports AVX2 — 8 floats per instruction.
The Apple M3 supports Neon — 4 floats per instruction, but with wider execution units and more of them.

For our Stage 3 inner loop:
```zig
for (0..p) |j| {
    result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
}
```

**Scalar execution** (one float per instruction):
- Load `b_ptr[j]` → multiply by `a_val` → load `result_ptr[j]` → add → store. Repeat 1024 times.

**AVX2 SIMD execution** (8 floats per instruction):
- Load `b_ptr[j..j+7]` — **8 floats at once**.
- Fused Multiply-Add: `result[j..j+7] += a_val × b_ptr[j..j+7]` — **8 FMAs in one instruction**.
- Store `result[j..j+7]`.
- Repeat 128 times (1024 / 8).

**8× fewer iterations. 8× fewer instructions.** This is where C++'s 400ms on the i5 comes from vs. pure scalar code's theoretical ~3,200ms.

### 4.2 — Why `-ffast-math` Is the Key

IEEE 754 requires that `(a + b) + c` produce the same result as computing it in that exact sequence. For the compiler to vectorize our accumulation loop, it needs to group 8 elements and process them simultaneously — changing the order of additions. Under strict IEEE 754, this is technically illegal, as it may change the last significant bit of floating-point results.

`-ffast-math` tells the compiler: **"I give you permission to reorder floating-point operations for throughput. I don't require strict IEEE 754 reproducibility."**

With that permission, the compiler generates:
```asm
; AVX2 code for the inner j-loop (conceptually):
VMOVSS      ymm0, [a_val]        ; broadcast a_val into all 8 lanes
VFMADD231PS ymm1, ymm0, [B+j*4]  ; result[j..j+7] += a_val * B[j..j+7]
; (one instruction replaces 8 scalar multiply-add sequences)
```

The `VFMADD231PS` instruction is a **Fused Multiply-Add** — it computes `a + b×c` with a single rounding step, at 8 floats per instruction. On Skylake, two of these can execute per clock cycle. That's 16 FMAs/cycle × 2.4 GHz = **38.4 billion FMAs per second** (theoretical peak). Our 400ms result represents about 5.4 GFLOPs/s — roughly 14% of theoretical peak, which is respectable for a non-BLAS implementation.

**Without `-ffast-math`**: the compiler emits scalar code or limited SSE2 code. You leave ~8× performance on the table.

**The tradeoff**: Results may differ in the least significant bit from a strictly IEEE-754 sequential computation. For matrix multiplication as a benchmark, this is undetectable. For financial calculations or reproducible scientific simulations, you cannot use `-ffast-math`.

### 4.3 — Why the M3 Converged All Three Languages

On the M3, Stage 3 gave Rust 83ms, C++ 83ms, Zig 89ms — all within 7%. On the i5, C++ was 419ms and Zig was 865ms — a 2× gap with the same stage.

The M3 differences:
1. **Wider out-of-order execution**: The M3 can track many more in-flight instructions simultaneously, allowing it to hide latencies between instructions that trip up the narrower Skylake pipeline.
2. **Larger L1/L2**: The M3's 128KB L1 (vs. Skylake's 64KB(2 cores, 32KB each)) means more of the working set fits in the fastest cache. Differences in code quality that manifest as extra loads on i5 are invisible on M3 because everything is in L1 anyway.
3. **Better branch prediction**: The M3's more sophisticated branch predictor makes the loop overhead in less-optimized code less costly.

The lesson: **a more powerful CPU makes it easier to write code that "accidentally" performs well.** This is dangerous. Code that seems equally fast across languages on an M3 may be 2× different on a Skylake server in your production cluster.

---

## Part 5: Cache Blocking — When Even Sequential Isn't Enough

### 5.1 — The Residual Problem

Stage 3's `(i,k,j)` loop is perfectly sequential in the innermost `j` loop. But there's a subtler issue at work for our 1024×1024 matrices.

Consider the working set for one full pass through the `k` loop (with `i` fixed):
- We read all of Matrix B: 1024 rows × 1024 floats × 4 bytes = **4 MB**
- The L3 cache on the i5 is **3 MB**

Matrix B doesn't fit in L3. As `k` cycles through all 1024 values, we repeatedly evict B's rows and re-fetch them. We're reading B from RAM multiple times per result row. This is why Stage 3 on the i5 didn't hit theoretical SIMD peak.

Cache blocking solves this by operating on sub-matrices small enough to fit in L1/L2:

```c
// cpp/matrix.cpp — Stage 4: 64×64 Cache-Blocked
#define BLOCK_SIZE 64
// A 64×64 block = 64 × 64 × 4 bytes = 16 KB
// Three blocks (A, B, Result) = 48 KB → fits in L2 (256 KB)

for (size_t ii = 0; ii < a_rows; ii += BLOCK_SIZE) {
    for (size_t kk = 0; kk < a_cols; kk += BLOCK_SIZE) {
        for (size_t jj = 0; jj < b_cols; jj += BLOCK_SIZE) {
            // Process only the 64×64 intersection of these blocks
            for (size_t i = ii; i < min(ii + BLOCK_SIZE, a_rows); ++i) {
                for (size_t k = kk; k < min(kk + BLOCK_SIZE, a_cols); ++k) {
                    float a_val = a_ptr[i * a_cols + k];
                    for (size_t j = jj; j < min(jj + BLOCK_SIZE, b_cols); ++j) {
                        result_ptr[i * b_cols + j] += a_val * b_ptr[k * b_cols + j];
                    }
                }
            }
        }
    }
}
```

Within a 64×64 block, the same 16KB of B is reused 64 times (once per row of A in the block) before moving to the next block. That 16KB stays in L1 cache throughout those 64 reuses. No RAM fetches for B during block processing — only L1 hits.

### 5.2 — The Stage 4 Paradox: Three Different Outcomes

Results:

| | i5 Stage 3 | i5 Stage 4 | Delta | M3 Stage 3 | M3 Stage 4 | Delta |
|:---|:---:|:---:|:---:|:---:|:---:|:---:|
| **C++** | 419ms | 401ms | **-4%** | 83ms | 119ms | **+43%** |
| **Rust** | 785ms | 647ms | **-17%** | 83ms | 126ms | **+52%** |
| **Zig** | 865ms | 1,367ms | **+58%** | 89ms | 144ms | **+62%** |

Wait — **tiling made everything slower on the M3**. Every language regressed. On the i5, C++ improved, Rust improved, and only Zig regressed. On the M3, everything regressed.

Why? Because the M3's cache hierarchy is so large that Stage 3 already fit the working set comfortably in L2/L3. Matrix B (4MB) plus the result row (4KB) fit within the M3's L3 cache for many working patterns. There were few L3 misses to eliminate. Tiling's overhead (extra loop variables, `min()` calls, more complex control flow) exceeded its cache benefit.

The i5, with its 3MB L3, was genuinely cache-thrashing on Stage 3 in ways that tiling helped eliminate. The M3, with its much larger caches, was not.

**The insight**: Cache blocking is not universally beneficial. Its benefit depends on whether you are actually L3-cache-limited. On the M3, you often are not. **The correct block size is not 64×64 universally — it should be tuned to L1 size / 3 (for three matrices) on the specific hardware.** The M3's L1 is 128KB, suggesting block sizes around 100–120 (if the algorithm gains from it at all, given the larger caches).


**C++**: C++ was already near the compute-bound limit in Stage 3. The hardware prefetcher was working well for the `(i,k,j)` pattern. Tiling added some overhead (extra loop variables, `std::min()` calls) but the improvement in L1/L2 hit rate was approximately equal to that overhead. Net: nearly flat.

**Rust**: Rust's LLVM backend benefited from tiling because it gave the optimizer clearer loop bounds to work with. When LLVM sees bounded loops over small, known-size arrays, it is more confident in applying vectorization and register promotion. The tile size (64×64) is small enough that LLVM could reason about it completely. Net: meaningful improvement.

**Zig**: This is the most important result. Zig's Stage 3 `(i,k,j)` implementation was a single, clean, unbounded sequential loop. LLVM's auto-vectorizer identified it, proved it was safe, and generated AVX2 code. When we added the tiling code — the extra `while` loops, the `@min()` calls, the block boundary variables — we introduced **conditional branching and ambiguous loop bounds** that the auto-vectorizer could no longer reason through. The vectorizer fell back to scalar code. The algorithmic improvement (better cache reuse) was not enough to compensate for losing AVX2(i5) and  ARM NEON(M3)vectorization.

### 5.3 — The Zig Regression: The Compiler Interference Principle

Across both architectures, Zig regressed on tiling by ~60%. But the mechanism is a compiler behavior, not a hardware behavior.

**Zig Stage 3** inner loop:
```zig
for (0..p) |j| {  // 0 to 1024, clean bounds, no conditionals
    result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
}
```
LLVM's auto-vectorizer sees: clean `for` loop with fixed trip count (1024 iterations), sequential pointer arithmetic, no aliasing concerns. It proves safety trivially. Result: AVX2/Neon vectorized code.

**Zig Stage 4** inner loop:
```zig
const j_end = @min(jj + BLOCK_SIZE, p);  // runtime computation
while (j < j_end) : (j += 1) {           // while loop, not for
    result_ptr[i * p + j] += a_val * b_ptr[k * p + j];
}
```
Now LLVM sees: `while` loop with a runtime-computed bound (`@min(jj + BLOCK_SIZE, p)`). The bound depends on two variables. LLVM must prove that the inner loop count is consistent, that the pointer arithmetic doesn't alias, and that the vectorized version produces equivalent results. The `@min()` call introduces a data-dependent branch. LLVM's analysis becomes uncertain. It falls back to scalar code.

Scalar code on a 6× more complex loop structure vs. vector code on a simple loop: Zig Stage 4 loses.

**The fix** (for a hypothetical Stage 6) would be to use Zig's `@Vector` type to write the SIMD operations explicitly, removing the auto-vectorizer from the equation entirely:
```zig
const Vec8 = @Vector(8, f32);
// explicit 8-wide FMA operations
```

---

## Part 6: The C ABI — How Three Languages Share One Binary

### 6.1 — What "ABI" Means at the Machine Level

The Application Binary Interface defines the protocol for compiled code to call other compiled code. It specifies:
- Which CPU registers carry function arguments and return values
- How the call stack is structured
- How symbol names appear in the compiled object file
- How the caller and callee negotiate stack cleanup

The **C ABI** (System V AMD64 on Linux, Microsoft x64 on Windows, ARM64 AAPCS on macOS/ARM) is the universal interoperability layer. Every language that wants to speak to other languages must be able to produce or consume the C ABI.

Our three languages declare their functions with C ABI explicitly:

```zig
// Zig: 'export' keyword = C ABI + visible symbol
export fn zig_matrix_multiply(
    a_ptr: [*]const f32, a_rows: usize, ...
) void { ... }
```

```rust
// Rust: extern "C" + #[no_mangle] = C ABI + unmangled symbol name
#[no_mangle]
pub unsafe extern "C" fn rust_matrix_multiply(
    a_ptr: *const f32, a_rows: usize, ...
) { ... }
```

```cpp
// C++: extern "C" disables C++ name mangling
extern "C" {
    void cpp_matrix_multiply(const float* a_ptr, size_t a_rows, ...) { ... }
}
```

The benchmark harness calls all three from Zig via `@cImport` (for C++) and `extern fn` declarations (for Zig and Rust). At runtime, all three calls are direct function calls at the machine code level — no marshaling, no copies, no overhead. The cost of the call itself is about 5–10 CPU cycles.

### 6.2 — Windows-Specific Linking: Rust's Transitive System Dependencies

When you link a Rust `staticlib` into a Zig binary on Windows, you inherit all of Rust's transitive system dependencies. These showed up as a late-stage linker error:

```
error: lld-link: undefined symbol: GetUserProfileDirectoryW
    note: referenced by libmatrix_rs.a
    note:               in std::env::home_dir::h90a4e1295df00731
```

Rust's standard library calls `GetUserProfileDirectoryW` (from `userenv.dll`) as part of its initialization, even though our code never calls `std::env::home_dir()`. The call is embedded in Rust's runtime initialization path — a transitive dependency.

Zig's linker (lld) is explicit: it will not silently link system libraries you didn't request. You must declare them in `build.zig`:

```zig
if (target.result.os.tag == .windows) {
    bench.linkSystemLibrary("user32");
    bench.linkSystemLibrary("kernel32");
    bench.linkSystemLibrary("ws2_32");
    bench.linkSystemLibrary("advapi32");
    bench.linkSystemLibrary("ntdll");
    bench.linkSystemLibrary("userenv");  // GetUserProfileDirectoryW
    bench.linkSystemLibrary("shell32");  // Transitive from userenv
}
```

This explicitness is a feature, not a bug. It forces you to understand your complete dependency graph — something that matters enormously in production systems where unexpected DLL dependencies can cause deployment failures.

---
## Part 8: The Register Micro-kernel — Taking Control of the Hardware

### 8.1 — Why Auto-Vectorization Failed

Stage 4 revealed a fundamental limitation: LLVM's auto-vectorizer could not analyze the tiled loop structure. The `@min()` runtime bounds, the `while` loop construct, and the 6-level nesting depth exceeded the optimizer's analysis budget. The vectorizer gave up and emitted scalar code.

This manifested identically across architectures: Zig regressed by ~60% on both x86_64 and ARM64. The failure was in the compiler's optimizer, not the hardware.

The fix is not better flags. The fix is not simpler loops. The fix is: **write the SIMD operations yourself**.

### 8.2 — The 4×4 Register Micro-kernel Architecture

The key insight from the BLAS (Basic Linear Algebra Subprograms) literature: the innermost computation unit should be a small fixed-size tile that lives entirely in CPU registers.

For a 4×4 micro-kernel:
- **C tile**: 4 rows × 4 columns = 16 floats → 4 SIMD registers (4 floats each)
- **B vector**: 1 row × 4 columns = 4 floats → 1 SIMD register
- **A values**: 4 scalars (one per row of C) → broadcast into SIMD registers

```
Register layout for one micro-kernel invocation:

    B vector (loaded once per k):
    ┌─────────────────────────┐
    │ B[k,j] B[k,j+1] B[k,j+2] B[k,j+3] │  → 1 SIMD register
    └─────────────────────────┘

    C tile (4 SIMD registers, accumulated across all k):
    ┌─────────────────────────┐
    │ C[i,j]   C[i,j+1]   C[i,j+2]   C[i,j+3]   │  → xmm0 / v0
    │ C[i+1,j] C[i+1,j+1] C[i+1,j+2] C[i+1,j+3] │  → xmm1 / v1
    │ C[i+2,j] C[i+2,j+1] C[i+2,j+2] C[i+2,j+3] │  → xmm2 / v2
    │ C[i+3,j] C[i+3,j+1] C[i+3,j+2] C[i+3,j+3] │  → xmm3 / v3
    └─────────────────────────┘

    For each k iteration:
      b_vec = load B[k, j..j+3]                    // 1 memory load
      c_row0 += broadcast(A[i, k]) * b_vec          // FMA: no memory load for C!
      c_row1 += broadcast(A[i+1, k]) * b_vec        // reuse b_vec from register
      c_row2 += broadcast(A[i+2, k]) * b_vec        // reuse b_vec from register
      c_row3 += broadcast(A[i+3, k]) * b_vec        // reuse b_vec from register
```

**Memory traffic per k iteration**: 1 B-vector load (4 floats) + 4 A-scalar loads = **20 bytes**. Compare to scalar code which loads 4 B values + 4 A values + 16 C values = **96 bytes per k iteration**. The micro-kernel reduces memory traffic by **5×** by keeping C in registers.

### 8.3 — Explicit SIMD Across Three Languages

Each language provides different mechanisms for expressing the same register-level operation:

**Zig** — `@Vector(4, f32)`:
```zig
const b_vec: @Vector(4, f32) = b_row[kk * p + j_start ..][0..4].*;
c_row0 += @as(@Vector(4, f32), @splat(a_ptr[i0 * n + kk])) * b_vec;
```
Zig's `@Vector` is a first-class type. `@splat` broadcasts a scalar into all lanes. LLVM maps this directly to SSE/AVX on x86 or NEON on ARM. No intrinsics needed.

**C++** — `__attribute__((vector_size(16)))`:
```cpp
typedef float v4f __attribute__((vector_size(16)));
v4f b_vec = *(const v4f*)&b_ptr[kk * b_cols + j_start];
v4f a_broadcast = {a_val, a_val, a_val, a_val};
c_row0 += a_broadcast * b_vec;
```
GCC/Clang vector extensions provide operator overloading for SIMD vectors. The critical addition is `__restrict` on pointers — without it, the compiler cannot prove that the C-tile register values remain valid after stores.

**Rust** — unrolled scalars with aliasing guarantees:
```rust
let a_val = *a_ptr.add(i0 * a_cols + kk);
let b0 = *b_ptr.add(kk * b_cols + j_start + 0);
let b1 = *b_ptr.add(kk * b_cols + j_start + 1);
let b2 = *b_ptr.add(kk * b_cols + j_start + 2);
let b3 = *b_ptr.add(kk * b_cols + j_start + 3);
c00 += a_val * b0; c01 += a_val * b1;
c02 += a_val * b2; c03 += a_val * b3;
```
Rust doesn't need explicit vector types because its ownership model guarantees no aliasing between `a_ptr`, `b_ptr`, and `result_ptr`. LLVM trusts Rust's `noalias` annotations and promotes the 16 local accumulator variables into SIMD registers.

### 8.4 — The Hierarchical Cache Funnel

Stage 4 used a single tiling level. Stage 5 uses three levels that map to the physical cache hierarchy:

```
Data flow: RAM → L3 → L2 → L1 → Registers

┌─────────────────────────────────────────────────────────┐
│ L3 Loop (block = 496 on i5-6300U)                       │
│   ┌─────────────────────────────────────────────────┐   │
│   │ L2 Loop (block = 144)                           │   │
│   │   ┌─────────────────────────────────────────┐   │   │
│   │   │ L1 Loop (block = 48)                    │   │   │
│   │   │   ┌─────────────────────────────────┐   │   │   │
│   │   │   │ Register Micro-kernel (4×4)     │   │   │   │
│   │   │   │ 16 C values in SIMD registers   │   │   │   │
│   │   │   │ No L1 pressure from C tile      │   │   │   │
│   │   │   └─────────────────────────────────┘   │   │   │
│   │   └─────────────────────────────────────────┘   │   │
│   └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

Block sizes are computed at runtime from the host CPU's actual cache sizes. The formula:

```
block = sqrt(cache_size × utilization_percent / (3 × sizeof(f32)))
```

The divisor of 3 accounts for the three working matrices (A tile, B tile, C tile — though in Stage 5, C is in registers, allowing higher utilization percentages).

| Cache Level | i5-6300U size | Utilization | Block Size |
|:---|:---:|:---:|:---:|
| L1 | 32 KB | 100% | 48 |
| L2 | 256 KB | 95% | 144 |
| L3 | 3 MB | 95% | 496 |

The 100% L1 utilization is safe because the C tile lives in registers, not L1. Only A and B tiles compete for L1 space.

### 8.5 — The `__restrict` Story in C++

C++ pointers can legally alias — `result_ptr[0]` might be the same memory location as `a_ptr[0]`. The compiler must conservatively assume this unless told otherwise.

Without `__restrict`:
```cpp
// Compiler must reload a_val after every store to result_ptr
// because the store MIGHT have modified a_ptr's data
result_ptr[i * b_cols + j] += a_val * b_vec;
// ↑ This store invalidates all loads from a_ptr and b_ptr
```

With `__restrict`:
```cpp
void cpp_matrix_multiply(
    const float* __restrict a_ptr, ...,
    float* __restrict result_ptr, ...)
// Now the compiler KNOWS stores to result_ptr cannot affect a_ptr or b_ptr
// It can keep a_val and c_rows in registers across iterations
```

This is why C++ was the hardest to optimize to parity with Zig and Rust. Zig's `[*]const f32` provides similar aliasing guarantees by default (const pointers cannot alias mutable pointers). Rust's ownership model makes aliasing impossible by construction.

---

## Part 9: The Mental Models You Now Own

After working through this document, you should be able to reason from these models without looking anything up.

### Model 1: RAM Is a 1D Tape
Memory is one-dimensional. Multi-dimensional arrays are a compiler convenience over that tape. Every time your code accesses memory "across" the natural storage order (stride access), you pay a cache miss penalty. Design your data structures and loops around physical layout, not mathematical abstraction.

### Model 2: The Cache Line Is Currency
You spend 64 bytes of cache bandwidth every time you touch a new cache line. If you only use 4 of those 64 bytes, you wasted 94% of your bandwidth. Make the innermost loop march forward through memory and use every byte of every cache line it loads.

### Model 3: The Compiler Is a Collaborator
Your job is to write code the compiler can analyze clearly. Simple, bounded, sequential loops are vectorizable. Loops with runtime-computed bounds, data-dependent conditions, and complex pointer arithmetic are not. The optimizer cannot vectorize what it cannot prove safe. When Zig's Stage 4 regressed, it was because our code became too complex for LLVM to analyze, not because the algorithm was wrong.

### Model 4: Hardware Quality Can Mask Compiler Quality
Stage 3 showed a 2× C++ advantage over Zig on the i5, but that gap nearly vanished on the M3. The M3's larger caches and wider execution engine compensated for Zig's slightly lower code quality. **Always benchmark on your weakest deployment hardware.**

### Model 5: Patterns Reproduce Across Architectures
The Stage 4 Zig regression was +58% on x86_64 and +62% on ARM64. Cache miss improvement ratios from loop reordering were in the same order-of-magnitude range on both. Physics is consistent. Trust ratios and patterns more than absolute numbers.

### Model 6: Measure, Then Optimize. Then Measure Again.
Cache blocking is a textbook optimization from the BLAS literature. On the i5, it helped C++ and Rust. On the M3, it hurt all three. The "correct" optimization depends on the target hardware's cache size. There is no universal answer. Measure on your target, not on your development machine.

### Model 7: When the Auto-Vectorizer Fails, Write the SIMD Yourself
The auto-vectorizer is a heuristic system with a finite analysis budget. Complex loop nests, runtime-computed bounds, and potential aliasing exhaust that budget. When this happens, the fix is not better flags or simpler code structure — it is **explicit SIMD**. Every systems language provides this capability. A 4×4 register micro-kernel transforms the innermost loop from "please vectorize this" to "execute these vector instructions." The compiler becomes a translator, not an optimizer. Stage 5 proved this: the language that suffered the worst auto-vectorization failure (Zig, +58% regression in Stage 4) became the fastest (135ms) once SIMD was made explicit.

---

*Grounded in benchmark data from an Intel Core i5-6300U (Skylake, 2015) running Windows/MSYS2, and an Apple M3 (ARM64, 2024) running macOS. All source code, flags, and results are documented in PERFORMANCE_LOG.md. The automated stage runner (`run_benchmark_stages.sh`) allows anyone to reproduce all measurements from scratch. Each stage has immutable kernel snapshots for all three languages — no git archaeology needed.*