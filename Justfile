# Justfile for matrix multiplication benchmark automation
# Install just: https://github.com/casey/just
# Windows: choco install just OR winget install just
# Linux: cargo install just OR apt install just

set shell := ["bash", "-uc"]

rust_target := `case "$(uname -s):$(uname -m)" in Darwin:arm64) echo aarch64-apple-darwin ;; Darwin:x86_64) echo x86_64-apple-darwin ;; Linux:arm64|Linux:aarch64) echo aarch64-unknown-linux-gnu ;; Linux:x86_64) echo x86_64-unknown-linux-gnu ;; MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64) echo x86_64-pc-windows-gnu ;; *) echo unsupported-target >&2; exit 1 ;; esac`
linux_rust_target := `case "$(uname -m)" in arm64|aarch64) echo aarch64-unknown-linux-gnu ;; x86_64) echo x86_64-unknown-linux-gnu ;; *) echo unsupported-linux-arch >&2; exit 1 ;; esac`
macos_rust_target := `case "$(uname -m)" in arm64|aarch64) echo aarch64-apple-darwin ;; x86_64) echo x86_64-apple-darwin ;; *) echo unsupported-macos-arch >&2; exit 1 ;; esac`

# Default target - build and run benchmark
default: run

# Build Rust static library
build-rust:
    @echo "🔨 Building Rust library for {{rust_target}}..."
    cd rust && RUSTFLAGS="-C target-cpu=native" cargo build --release --target {{rust_target}}
    @echo "✅ Rust library built"

# Build Rust for Linux
build-rust-linux:
    @echo "🔨 Building Rust library for Linux target {{linux_rust_target}}..."
    cd rust && RUSTFLAGS="-C target-cpu=native" cargo build --release --target {{linux_rust_target}}
    @echo "✅ Rust library built"

# Build Rust for macOS
build-rust-macos:
    @echo "🔨 Building Rust library for macOS target {{macos_rust_target}}..."
    cd rust && RUSTFLAGS="-C target-cpu=native" cargo build --release --target {{macos_rust_target}}
    @echo "✅ Rust library built"

# Clean all build artifacts
clean:
    @echo "🧹 Cleaning build artifacts..."
    zig build clean
    cd rust && cargo clean
    rm -rf .zig-cache zig-cache zig-out
    @echo "✅ Clean complete"

# Build Zig benchmark (Debug)
build-debug: build-rust
    @echo "🔨 Building Zig benchmark (Debug)..."
    zig build

# Build Zig benchmark (ReleaseFast)
build-release: build-rust
    @echo "🔨 Building Zig benchmark (ReleaseFast)..."
    zig build -Doptimize=ReleaseFast

# Run benchmark (Debug)
run-debug: build-debug
    @echo "🚀 Running benchmark (Debug)..."
    zig build run

# Run benchmark (ReleaseFast)
run: build-release
    @echo "🚀 Running benchmark (ReleaseFast)..."
    zig build -Doptimize=ReleaseFast run

# Run benchmark multiple times for stats
bench: build-release
    @echo "📊 Running benchmark 5 times..."
    @for i in 1 2 3 4 5; do \
        echo "\n--- Run $$i ---"; \
        zig build -Doptimize=ReleaseFast run; \
    done

# Run with different matrix sizes
bench-sizes: build-release
    @echo "📊 Benchmarking different matrix sizes..."
    @echo "100x50 * 50x100"
    @zig build -Doptimize=ReleaseFast run
    @echo "\n200x100 * 100x200"
    @# Modify matrix sizes in bench.zig or use build options
    @echo "Run with modified matrix sizes"

# Quick check (fast compile, no Rust rebuild if exists)
quick: build-rust
    @echo "🔨 Quick build (cached)..."
    zig build -Doptimize=ReleaseFast run

# Watch mode (requires watchexec)
watch:
    @echo "👀 Watching for changes..."
    watchexec -r -e zig,cpp,rs just run

# Install development tools
setup:
    @echo "📦 Installing development tools..."
    @echo "Installing just..."
    cargo install just || echo "Install just manually: https://github.com/casey/just"
    @echo "\nInstalling watchexec for watch mode..."
    cargo install watchexec-cli || echo "Install watchexec manually"
    @echo "\nInstalling cargo-watch..."
    cargo install cargo-watch || echo "Install cargo-watch manually"
    @echo "✅ Setup complete"

# List all available commands
list:
    @just --list

# Help
help:
    @echo "Available commands:"
    @echo "  just run           - Build (ReleaseFast) and run benchmark"
    @echo "  just bench         - Run benchmark 5 times"
    @echo "  just build-release - Build only (ReleaseFast)"
    @echo "  just clean         - Clean all build artifacts"
    @echo "  just watch         - Watch for changes and auto-run"
    @echo "  just setup         - Install development tools"
