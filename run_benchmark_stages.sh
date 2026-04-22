#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/matrix-stages.XXXXXX")"
KEEP_WORKTREES="${KEEP_WORKTREES:-0}"

# Ensure cargo/rustup/zig are on PATH.
# On macOS/Linux, $HOME/.cargo/bin is the standard location.
# On Windows (Git Bash / MSYS2), $HOME is /home/user but cargo lives
# under the Windows profile. We check both without calling cmd.exe.
_cargo_dirs=("$HOME/.cargo/bin" "/c/Users/$(whoami)/.cargo/bin")
for _d in "${_cargo_dirs[@]}"; do
    if [[ -d "$_d" ]] && ! command -v cargo >/dev/null 2>&1; then
        export PATH="$_d:$PATH"
        break
    fi
done

declare -a WORKTREES=()

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing command: %s\n' "$1" >&2
        exit 1
    }
}

detect_host() {
    case "$(uname -s):$(uname -m)" in
        Darwin:arm64|Darwin:aarch64)
            RUST_TARGET="aarch64-apple-darwin"
            CXX_RUNTIME="c++"
            ;;
        Darwin:x86_64)
            RUST_TARGET="x86_64-apple-darwin"
            CXX_RUNTIME="c++"
            ;;
        Linux:arm64|Linux:aarch64)
            RUST_TARGET="aarch64-unknown-linux-gnu"
            CXX_RUNTIME="stdc++"
            ;;
        Linux:x86_64)
            RUST_TARGET="x86_64-unknown-linux-gnu"
            CXX_RUNTIME="stdc++"
            ;;
        MINGW64_NT-*:x86_64|MSYS_NT-*:x86_64|CYGWIN_NT-*:x86_64)
            RUST_TARGET="x86_64-pc-windows-gnu"
            CXX_RUNTIME="stdc++"
            ;;
        *)
            printf 'unsupported host: %s:%s\n' "$(uname -s)" "$(uname -m)" >&2
            exit 1
            ;;
    esac
}

cleanup() {
    local exit_code=$?

    if [[ "$KEEP_WORKTREES" != "1" ]]; then
        if ((${#WORKTREES[@]} > 0)); then
            for worktree in "${WORKTREES[@]}"; do
                git -C "$ROOT_DIR" worktree remove --force "$worktree" >/dev/null 2>&1 || true
            done
        fi
        rm -rf "$TMP_ROOT"
    else
        printf 'kept worktrees in %s\n' "$TMP_ROOT" >&2
    fi

    exit "$exit_code"
}

trap cleanup EXIT

add_worktree() {
    local name="$1"
    local commit="$2"
    local dir="$TMP_ROOT/$name"

    git -C "$ROOT_DIR" worktree add --detach "$dir" "$commit" >/dev/null
    WORKTREES+=("$dir")
    printf '%s\n' "$dir"
}

prepare_modern_build() {
    local dir="$1"
    cp "$ROOT_DIR/build.zig" "$dir/build.zig"
}

prepare_rust_crate_root() {
    local dir="$1"
    cp "$ROOT_DIR/rust/src/lib.rs" "$dir/rust/src/lib.rs"
}

prepare_benchmark_harness() {
    local dir="$1"
    cp "$ROOT_DIR/bench/bench.zig" "$dir/bench/bench.zig"
}

# Copy the cache detection infrastructure (required by bench.zig)
prepare_cache_infrastructure() {
    local dir="$1"
    mkdir -p "$dir/bench/cache"
    cp "$ROOT_DIR/bench/cache_info.zig" "$dir/bench/cache_info.zig"
    cp "$ROOT_DIR/bench/cache/"*.zig "$dir/bench/cache/"
}

# Copy stage-matched Zig kernel → zig/matrix.zig in worktree
prepare_stage_matched_zig_kernel() {
    local dir="$1"
    local stage="$2"
    local src="$ROOT_DIR/zig/matrix_${stage}.zig"

    if [[ ! -f "$src" ]]; then
        printf 'missing stage-matched Zig kernel: %s\n' "$src" >&2
        exit 1
    fi

    cp "$src" "$dir/zig/matrix.zig"
}

# Copy stage-matched C++ kernel → cpp/matrix.cpp in worktree
prepare_stage_matched_cpp_kernel() {
    local dir="$1"
    local stage="$2"
    local src="$ROOT_DIR/cpp/matrix_${stage}.cpp"

    if [[ ! -f "$src" ]]; then
        printf 'missing stage-matched C++ kernel: %s\n' "$src" >&2
        exit 1
    fi

    cp "$src" "$dir/cpp/matrix.cpp"
}

# Copy stage-matched Rust kernel → rust/src/matrix.rs in worktree
prepare_stage_matched_rust_kernel() {
    local dir="$1"
    local stage="$2"
    local src="$ROOT_DIR/rust/src/matrix_${stage}.rs"

    if [[ ! -f "$src" ]]; then
        printf 'missing stage-matched Rust kernel: %s\n' "$src" >&2
        exit 1
    fi

    cp "$src" "$dir/rust/src/matrix.rs"
}

build_rust() {
    local dir="$1"
    local rustflags="$2"

    if [[ -n "$rustflags" ]]; then
        (
            cd "$dir/rust"
            RUSTFLAGS="$rustflags" cargo build --release --target "$RUST_TARGET"
        )
    else
        (
            cd "$dir/rust"
            cargo build --release --target "$RUST_TARGET"
        )
    fi
}

run_zig() {
    local dir="$1"
    shift

    (
        cd "$dir"
        zig build run "$@"
    )
}

# Thermal cooldown between stages.
# On low-TDP CPUs (e.g. 15W i5-6300U), sustained heavy compute causes thermal
# throttling, which can degrade results by 2× or more. A brief pause lets the
# CPU return to boost clocks. Skip on CI (detected via $CI).
thermal_cooldown() {
    if [[ "${CI:-}" == "true" ]]; then
        return  # CI runners have active cooling; skip
    fi
    printf 'Cooling down (5s)...\n'
    sleep 5
}

run_stage() {
    local label="$1"
    local commit="$2"
    local rustflags="$3"
    shift 3

    local dir
    printf '\n=== %s (%s) [stage-matched] ===\n' "$label" "$commit"
    dir="$(add_worktree "$label" "$commit")"

    # Always use the modern build.zig — it handles all targets via
    # rustTargetTriple() and registers the cache_info module needed by bench.zig.
    prepare_modern_build "$dir"

    # Copy all stage-matched kernels (immutable snapshots)
    prepare_stage_matched_zig_kernel "$dir" "$label"
    prepare_stage_matched_cpp_kernel "$dir" "$label"
    cp "$ROOT_DIR/cpp/matrix.h" "$dir/cpp/matrix.h"   # modern 10-param header
    prepare_stage_matched_rust_kernel "$dir" "$label"
    prepare_rust_crate_root "$dir"
    prepare_benchmark_harness "$dir"
    prepare_cache_infrastructure "$dir"

    build_rust "$dir" "$rustflags"
    run_zig "$dir" "$@"
}

run_current() {
    local head
    head="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"

    printf '\n=== stage5 (%s) [current] ===\n' "$head"
    build_rust "$ROOT_DIR" "-C target-cpu=native"
    run_zig "$ROOT_DIR" -Doptimize=ReleaseFast
}

main() {
    local cmd

    for cmd in bash git rustup cargo zig sed cp mktemp uname; do
        require_cmd "$cmd"
    done

    detect_host

    printf 'Host target: %s\n' "$RUST_TARGET"
    printf 'Using stage-matched kernels for all languages (zig, cpp, rust)\n'
    rustup target add "$RUST_TARGET"

    run_stage stage1 f81426b "" -Doptimize=ReleaseFast
    thermal_cooldown
    run_stage stage2 906609d "-C target-cpu=native" -Doptimize=ReleaseFast -Dtarget=native
    thermal_cooldown
    run_stage stage3 c7c6d4c "-C target-cpu=native" -Doptimize=ReleaseFast -Dtarget=native
    thermal_cooldown
    run_stage stage4 32f7d90 "-C target-cpu=native" -Doptimize=ReleaseFast -Dtarget=native
    thermal_cooldown
    run_current
}

main "$@"
