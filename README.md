# Matrix-Lib: A Polyglot Systems Performance Journey

A high-performance exploration of **Zig**, **Rust**, and **C++** interoperability, documenting the evolution from naive implementation to hardware-synchronized optimization.

```text
    [ Infrastructure Layer ]
           |
    +------+------+------+
    |      |      |      |
  [Zig]  [Rust] [C++]  (Cache-Aware i,k,j Kernels)
    |      |      |
    +------+------+
           |
    [ Unified Build System (Zig) ]
```

## The Mission
This project is a recorded history of **Systems Thinking**. We started with a simple goal: multiply 1024x1024 matrices across three languages. We ended with a deep understanding of how the **CPU Cache** and **SIMD pipelines** dictate real-world performance.

---

## Lessons Learned: The Systems Mindset
1.  **Memory is Flat**: RAM is not a grid. It's a 1D line. Jumping across columns (stride) kills performance by trashing the CPU's Cache Lines.
2.  **Hardware Sympathy > Language War**: A well-configured C++ toolchain can outperform a naive Zig loop. The "fastest language" is the one that most easily allows you to speak to the hardware.
3.  **The "Loop Flip" Magic**: Changing the loop order from `(i, j, k)` to `(i, k, j)` resulted in a **48x speedup**. This single change had more impact than every other compiler flag combined.
4.  **Compiler Conflict**: Manual optimizations like Stage 4 "Blocking" can sometimes **slow down** your code if they confuse the compiler's built-in vectorization heuristics (as seen in our Zig results).

---

## Performance Summary: 1024x1024 Workload
*Total operations: ~2.1 Billion FLOPs.*

| Stage | Milestone | Zig | Rust | C++ |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Naive Baseline** | 10,414 ms | 12,826 ms | 12,820 ms |
| **3** | **Loop Flip (i,k,j)** | 865 ms | 785 ms | 419 ms |
| **4** | **Cache Blocking** | 1367 ms | **647 ms** | **401 ms** |

> 📜 **[Read the Full Performance History Log here](./PERFORMANCE_LOG.md)** for a step-by-step audit of the journey.

---

## Technical Masterclass: How the Optimization Works
We transitioned from "Math-Centric" loops to "Hardware-Centric" loops. This one change fundamentally altered how the CPU interacts with the 1D line of RAM.

> 🎓 **[Read the Deep Dive: The Mechanics of "Touching the Metal"](./DEEP_DIVE.md)** to understand Cache Locality, SIMD Vectorization, and why "Memory is a Flat Line."

---

## Build & Replicate
### Prerequisites
*   **Zig 0.15.2**
*   **Rust** (Target: `x86_64-pc-windows-gnu`)
*   **G++ 15.2.0** (MSYS2/MinGW)

### 1. Build the Rust Engine
```bash
cd rust
RUSTFLAGS="-C target-cpu=native" cargo build --release --target x86_64-pc-windows-gnu
cd ..
```

### 2. Run the Benchmark
```bash
# Clean artifacts
zig build clean

# Build and run the optimized harness
zig build run -Doptimize=ReleaseFast -Dtarget=native
```

---

## Conclusion: Hardware Sympathy
This project demonstrates that the ultimate performance limit is dictated by how well your code aligns with the CPU's cache hierarchy and vector units. **In systems engineering, we don't just write code that works; we write code that vibrates with the hardware.**
