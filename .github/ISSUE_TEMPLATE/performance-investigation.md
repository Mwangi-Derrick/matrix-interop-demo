---
name: Performance Investigation
about: Report performance anomaly or investigate optimization behavior
title: "[PERF] "
labels: performance, investigation
assignees: ''

---

## Performance Observation

### What did you observe?

[Describe the performance behavior you noticed]

### Test Conditions

**Hardware:**
- CPU: [e.g., Intel Core i7-9750H, Apple M3, etc.]
- Architecture: [x86_64, ARM64, etc.]
- OS: [Windows 11, macOS 14, Ubuntu 22.04, etc.]
- Memory: [RAM amount and configuration]

**Software:**
- Compiler versions: [Zig 0.15.2, Rust 1.75, Clang 18, etc.]
- Build flags: [optimization levels, target features]
- Matrix size: [1024x1024, etc.]

### Benchmark Results

**Stage Results:**
```
Stage 1: XXXX ms
Stage 2: XXXX ms
Stage 3: XXXX ms
Stage 4: XXXX ms
Stage 5: XXXX ms
```

**Language Comparison:**
```
Zig:   XXXX ms
Rust:  XXXX ms
C++:   XXXX ms
```

### Expected vs Actual

**Expected:** [What you thought would happen]
**Actual:** [What actually happened]
**Delta:** [How much it differs]

## Analysis

### What might explain this?

[Your hypothesis about why this happened]

### Related Factors

- [ ] Cache size/configuration
- [ ] Compiler optimization differences
- [ ] Memory alignment
- [ ] SIMD instruction availability
- [ ] Thermal throttling
- [ ] Other (specify)

## Reproduction Steps

```bash
# Commands to reproduce the issue
./run_benchmark_stages.sh
# or specific reproduction commands
```

## Additional Context

[Links to similar issues, relevant documentation, or external references]

---

**Want to investigate further?** Include benchmark output and hardware details!