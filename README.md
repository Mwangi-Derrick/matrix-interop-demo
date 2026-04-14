# Matrix-Lib: Systems Interoperability Benchmark

A high-performance exploration of modern systems programming, demonstrating how **Zig**, **Rust**, and **C++** can co-exist in a single, unified build system.

## The Mission
This project serves as a technical bridge. It isn't just about matrix multiplication; it's about proving that the "language wars" are secondary to **interoperability**. 

We use **Zig 0.15.2** as the primary orchestrator and build system, leveraging its ability to compile C++ and link Rust static libraries seamlessly.

### Why this project?
1.  **Learning Zig**: Zig is the "modern C"—it provides the manual control of C, the type-safety inspirations of TypeScript, and the performance of Rust, without the overhead of a hidden runtime.
2.  **The Interop Powerhouse**: We demonstrate a "Real World" architecture where:
    *   **C++** handles legacy or specialized math logic.
    *   **Rust** provides memory-safe, high-performance modules.
    *   **Zig** acts as the "glue" and the optimized entry point.
3.  **Cross-Language Relevance**: Systems libraries like this are rarely used in isolation. They form the "Engine" for higher-level applications.

---

## Architecture: The "Polyglot" Engine

### 1. The Core (Zig, Rust, C++)
Every implementation follows the C ABI to ensure zero-overhead calls between languages.

*   **Zig (`zig/matrix.zig`)**: Implements the matrix logic using Zig's strict but expressive syntax.
*   **Rust (`rust/src/matrix.rs`)**: Uses `#[no_mangle]` and `extern "C"` to expose safe Rust logic to the outside world.
*   **C++ (`cpp/matrix.cpp`)**: A standard C++ implementation wrapped in `extern "C"` for compatibility.

### 2. Extending to the Ecosystem (Real World Use)
In a production system, this `matrix_lib` would be distributed as a shared library (`.so`, `.dll`, or `.dylib`) to be consumed by:

*   **Python**: Via `ctypes` or `cffi`. Imagine a high-frequency trading bot where the strategy is in Python, but the heavy matrix math is powered by our Rust/Zig engine.
*   **TypeScript/Node.js**: Via `N-API` or `node-ffi-napi`. Perfect for Electron apps that need to process large datasets without locking the UI thread.
*   **Go**: Via `cgo`. Allows Go's concurrency model to handle web requests while the Zig engine handles the raw computation.

---

## Build Instructions

### Prerequisites
*   **Zig 0.15.2**
*   **Rust** (with the `x86_64-pc-windows-gnu` target)
*   **G++** (MinGW-w64/MSYS2)

### 1. Build the Rust Component
```bash
cd rust
cargo build --release --target x86_64-pc-windows-gnu
cd ..
```

### 2. Run the Benchmark
The Zig build system will automatically compile the C++ source, compile the Zig source, and link the Rust static library.

```bash
zig build run -Doptimize=ReleaseFast
```

---

## Insights
Zig's design philosophy—**no hidden control flow** and **comptime** power—makes it the ideal candidate for a modern build system that replaces complex Makefiles or CMake configurations. It treats C and C++ as first-class citizens, making it the perfect "glue" for the next generation of systems software.
