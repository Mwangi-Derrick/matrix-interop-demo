# Matrix Interop Demo 🦀⚡➕

**Zig · Rust · C++** — same math, zero overhead, one build system.

## Results (Apple M1)

| Language | Time (ms) | Binary Size |
|----------|-----------|-------------|
| Zig      | 47        | 124KB       |
| Rust     | 48        | 892KB       |
| C++      | 49        | 56KB        |

## Key Takeaways

- **C ABI is universal** — all three call each other with no marshaling
- **Zig builds everything** — no CMake, no Makefiles, no `build.rs`
- **Performance is identical** — pick based on ergonomics, not speed

## Run It

```bash
zig build run -Doptimize=ReleaseFast