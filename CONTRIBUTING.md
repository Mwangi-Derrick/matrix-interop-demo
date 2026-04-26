# Contributing to matrix-lib

> *"The best way to predict the future is to create it. The best way to create the future is to understand the past. The best way to understand the past is to study the physics of computation."*

---

## 🌟 Welcome, Systems Engineer

If you're reading this, you're probably one of those rare engineers who:

- **Gets excited** about cache line physics and memory hierarchies
- **Questions everything** — including why your favorite language "should" be fast
- **Measures before you believe** — and measures again to be sure
- **Knows that performance** isn't about syntax; it's about understanding what the CPU actually does
- **Has probably written** more assembly than application code
- **Believes** that "it depends" is the only honest answer to performance questions

**This project needs you.** We're not building another CRUD app or REST API. We're investigating the fundamental relationship between source code, compiler optimization, and hardware physics.

---

## 🚀 What We're Building

This isn't a typical open source project. We're conducting **reproducible, cross-platform performance archaeology** — using matrix multiplication as our probe to understand what actually governs speed in low-level systems code.

We run identical benchmarks across:
- **Multiple CPU architectures** (x86_64, ARM64, Apple Silicon)
- **Multiple compilers** (Clang, GCC, rustc, Zig)
- **Multiple optimization strategies** (naive loops → hierarchical tiling → SIMD micro-kernels)

Every finding is **verifiable, reproducible, and grounded in physics**. We don't declare winners. We explain why.

---

## 🎯 Ways to Contribute

### 1. **Performance Investigations** (Most Impactful)

**Add a new CPU architecture or compiler to our test matrix:**

We're currently testing on Intel Skylake, Apple M3, and CI runners. What about:
- AMD Zen 4 (Ryzen 7000 series)
- Intel Raptor Lake (13th/14th gen)
- ARM Graviton (AWS)
- RISC-V development boards
- Different compilers (ICC, MSVC, AOCC)

**Requirements:**
- Run `./run_benchmark_stages.sh` on your hardware
- Submit the output as a PR with hardware specs
- Explain any anomalies you observe

**Impact:** New data points help us understand if our findings are universal or architecture-specific.

### 2. **Algorithm Implementations**

**Implement a new optimization stage:**

We have 5 stages now. What about:
- **Stage 6:** BLIS-style micro-kernel with assembly intrinsics
- **Stage 7:** NUMA-aware algorithms for multi-socket systems
- **Stage 8:** GPU acceleration (CUDA/OpenCL)
- **Stage 9:** Distributed algorithms across multiple machines

**Requirements:**
- Implement in all three languages (Zig, Rust, C++)
- Follow the existing stage naming convention
- Include comprehensive comments explaining the algorithm
- Add benchmark results to your PR

### 3. **Cross-Platform Compatibility**

**Fix platform-specific issues:**

- NEON vectorization bugs in Rust on ARM64
- MSVC compatibility for Windows
- GCC-specific optimizations
- macOS/iOS deployment

### 4. **Documentation & Education**

**Help others understand systems performance:**

- Improve explanations in DEEP_DIVE.md
- Create tutorial walkthroughs
- Add visualizations of cache behavior
- Write about your findings on your blog (tag us!)

### 5. **Tooling & Automation**

**Improve our development workflow:**

- Better benchmark result analysis scripts
- Automated performance regression detection
- Cross-platform build system improvements
- CI/CD pipeline enhancements

---

## 🛠️ Getting Started

### Prerequisites

```bash
# Required toolchains
zig version 0.15.2+  # Our build orchestrator
rustc + cargo        # For Rust implementations
clang/gcc            # For C++ implementations

# Optional but recommended
hyperfine            # For precise benchmarking
perf/linux-tools     # For performance profiling
```

### Development Setup

```bash
# Clone the repository
git clone https://github.com/Mwangi-Derrick/matrix-interop-demo.git
cd matrix-lib

# Run all benchmark stages
./run_benchmark_stages.sh

# Run specific language benchmarks
zig build run-zig
cargo run --release
cd cpp && make && ./matrix_bench
```

### Testing Your Changes

```bash
# Run benchmarks and verify results match between languages
./run_benchmark_stages.sh

# Check that all stages produce identical numerical results
# (Different performance is OK, different answers are not)
```

---

## 📊 Contribution Guidelines

### Code Quality

- **Performance is paramount** — but correctness comes first
- **Comment aggressively** — explain not just what, but why
- **Follow existing patterns** — consistency across languages matters
- **Measure everything** — include benchmark results in PRs

### Pull Request Process

1. **Fork** the repository
2. **Create a feature branch** (`git checkout -b feature/amazing-optimization`)
3. **Implement your changes** with comprehensive comments
4. **Run benchmarks** and include results in your PR description
5. **Update documentation** if needed
6. **Submit PR** with detailed explanation of your findings

### PR Template

```markdown
## What This PR Does

[Brief description of the change]

## Performance Impact

[Include benchmark results before/after]

## Technical Details

[Explain the algorithm/optimization strategy]

## Testing

[How you verified correctness and performance]

## Related Issues

[Link to any related issues or discussions]
```

---

## 🎓 Learning Opportunities

### If You're New to Systems Performance

Start here:
1. Read [DEEP_DIVE.md](DEEP_DIVE.md) — it's a masterclass
2. Run `./run_benchmark_stages.sh` and observe the 40× speedup
3. Try implementing Stage 1 in your favorite language
4. Measure the performance difference when you change loop order

### Advanced Topics to Explore

- **Cache associativity** and how it affects tiling strategies
- **TLB (Translation Lookaside Buffer)** behavior with large matrices
- **NUMA (Non-Uniform Memory Access)** on multi-socket systems
- **SIMD register allocation** and spill-to-stack behavior
- **Branch prediction** and how it interacts with loop structures

### Recommended Reading

- **"What Every Programmer Should Know About Memory"** by Ulrich Drepper
- **"Computer Architecture: A Quantitative Approach"** by Hennessy & Patterson
- **BLIS micro-kernel documentation**
- **Intel Optimization Manuals** ( Volumes 1-4 )

---

## 🌍 Community & Discussion

### Where to Ask Questions

- **GitHub Issues:** For bugs, performance anomalies, or feature requests
- **GitHub Discussions:** For general questions about systems performance
- **PR Comments:** For detailed technical discussions

### Code of Conduct

We follow a simple principle: **Be excellent to each other.** Technical disagreements are welcome. Personal attacks are not. We're all here to learn.

### Recognition

Contributors who make significant performance improvements or add new architectures will be:
- Listed in [PERFORMANCE_LOG.md](PERFORMANCE_LOG.md)
- Acknowledged in release notes
- Invited to co-author future papers or talks

---

## 🚀 Your Journey Starts Here

**You don't need permission to start exploring.** Fork the repo, run the benchmarks, and start asking questions. What surprises you? What doesn't match your mental model? What do the numbers tell you about how computers actually work?

The most valuable contributions often start with: *"Wait, that's weird. Let me investigate..."*

Welcome to the community of engineers who measure, question, and understand. Let's build something that matters.

---

*"In the end, all engineering is about understanding constraints and working within them. The best engineers don't just accept constraints — they understand them deeply enough to bend them."*