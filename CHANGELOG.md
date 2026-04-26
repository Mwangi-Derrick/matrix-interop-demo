# Changelog

All notable changes to matrix-lib will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Open Source Infrastructure**
  - CONTRIBUTING.md with welcoming guidelines for HPC enthusiasts
  - LICENSE (MIT) for open source distribution
  - CODE_OF_CONDUCT.md emphasizing technical excellence
  - SECURITY.md for responsible disclosure
  - CHANGELOG.md for tracking changes

- **CI/CD Improvements**
  - More precise path-based triggers (only build on code changes)
  - Pull request validation for documentation
  - Better artifact naming and organization

### Changed
- **Repository Organization**
  - Moved scattered files into logical directories
  - Improved documentation structure
  - Enhanced contributor experience

## [0.1.0] - 2024-12-XX

### Added
- **Initial Release**: Cross-platform matrix multiplication performance investigation
- **Five Optimization Stages**: From naive loops to hierarchical SIMD micro-kernels
- **Three Language Implementations**: Zig, Rust, and C++
- **Multi-Architecture Testing**: x86_64, ARM64, Apple Silicon
- **Comprehensive Documentation**: DEEP_DIVE.md and PERFORMANCE_LOG.md
- **Automated Benchmarking**: `run_benchmark_stages.sh` with reproducible results

### Performance Findings
- **Stage 3 Loop Reordering**: 15-40× speedup across all architectures
- **Stage 5 Hierarchical + SIMD**: Best performance on 5 of 6 test machines
- **Cross-Architecture Consistency**: Same optimization patterns work everywhere
- **C++ Stage 5 Leadership**: Consistently fastest in final optimization stage

### Technical Infrastructure
- **Zig Build System**: Unified orchestration for all languages
- **Git Worktree Staging**: Immutable benchmark kernels
- **Thermal Management**: Cooldown periods between benchmark stages
- **Cross-Platform Compatibility**: Windows, macOS, Linux support

---

## Types of Changes

- `Added` for new features
- `Changed` for changes in existing functionality
- `Deprecated` for soon-to-be removed features
- `Removed` for now removed features
- `Fixed` for any bug fixes
- `Security` in case of vulnerabilities

## Versioning

We use [Semantic Versioning](https://semver.org/):

- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions
- **PATCH** version for backwards-compatible bug fixes

---

*"Every version tells a story. Every change teaches a lesson. Every release advances our understanding of systems."*