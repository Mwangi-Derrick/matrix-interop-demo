#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/matrix-stages.XXXXXX")"
KEEP_WORKTREES="${KEEP_WORKTREES:-0}"
USE_CURRENT_ZIG_ALL_STAGES="${USE_CURRENT_ZIG_ALL_STAGES:-0}"
USE_STAGE_MATCHED_ZIG="${USE_STAGE_MATCHED_ZIG:-1}"

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

patch_stage1_build() {
    local dir="$1"

    sed -i.bak \
        -e "s|x86_64-apple-darwin|${RUST_TARGET}|g" \
        -e "s|x86_64-unknown-linux-gnu|${RUST_TARGET}|g" \
        -e "s|bench.linkSystemLibrary(\"stdc++\");|bench.linkSystemLibrary(\"${CXX_RUNTIME}\");|" \
        "$dir/build.zig"

    rm -f "$dir/build.zig.bak"
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

prepare_current_zig_kernel() {
    local dir="$1"
    cp "$ROOT_DIR/zig/matrix.zig" "$dir/zig/matrix.zig"
}

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

run_stage() {
    local label="$1"
    local commit="$2"
    local rustflags="$3"
    shift 3

    local dir
    local zig_source_note=""
    if [[ "$USE_CURRENT_ZIG_ALL_STAGES" == "1" ]]; then
        zig_source_note=" [current-zig]"
    elif [[ "$USE_STAGE_MATCHED_ZIG" == "1" ]]; then
        zig_source_note=" [stage-matched-zig]"
    fi
    printf '\n=== %s (%s)%s ===\n' "$label" "$commit" "$zig_source_note"
    dir="$(add_worktree "$label" "$commit")"

    if [[ "$label" == "stage1" ]]; then
        patch_stage1_build "$dir"
    else
        prepare_modern_build "$dir"
    fi

    prepare_rust_crate_root "$dir"
    prepare_benchmark_harness "$dir"
    if [[ "$USE_CURRENT_ZIG_ALL_STAGES" == "1" ]]; then
        prepare_current_zig_kernel "$dir"
    elif [[ "$USE_STAGE_MATCHED_ZIG" == "1" ]]; then
        prepare_stage_matched_zig_kernel "$dir" "$label"
    fi
    build_rust "$dir" "$rustflags"
    run_zig "$dir" "$@"
}

run_current() {
    local head
    head="$(git -C "$ROOT_DIR" rev-parse --short HEAD)"

    printf '\n=== current (%s) ===\n' "$head"
    build_rust "$ROOT_DIR" "-C target-cpu=native"
    run_zig "$ROOT_DIR" -Doptimize=ReleaseFast -Dtarget=native
}

main() {
    local cmd

    for cmd in bash git rustup cargo zig sed cp mktemp uname; do
        require_cmd "$cmd"
    done

    detect_host

    printf 'Host target: %s\n' "$RUST_TARGET"
    if [[ "$USE_CURRENT_ZIG_ALL_STAGES" == "1" ]]; then
        printf 'Using current zig/matrix.zig for historical stages\n'
    elif [[ "$USE_STAGE_MATCHED_ZIG" == "1" ]]; then
        printf 'Using stage-matched Zig kernels (zig/matrix_stage{1..4}.zig)\n'
    fi
    rustup target add "$RUST_TARGET"

    run_stage stage1 f81426b "" -Doptimize=ReleaseFast
    run_stage stage2 906609d "-C target-cpu=native" -Doptimize=ReleaseFast -Dtarget=native
    run_stage stage3 c7c6d4c "-C target-cpu=native" -Doptimize=ReleaseFast -Dtarget=native
    run_stage stage4 32f7d90 "-C target-cpu=native" -Doptimize=ReleaseFast -Dtarget=native
    run_current
}

main "$@"
