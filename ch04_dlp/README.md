# Chapter 4 -- Data-Level Parallelism in Vector, SIMD and GPU Architectures

When the same operation applies to many data items, hardware can run them in lockstep. Three flavors:
**vector** machines (long vectors, pipelined or laned functional units, chaining), **SIMD** extensions
(short fixed-width vectors packed into registers) and **GPUs** (SIMT: thousands of threads grouped into warps that
execute one instruction at a time with masking). The 5th edition made this a main chapter.

## Examples

| Example | What it shows |
|---------|---------------|
| [`vector_lanes`](vector_lanes) | register file, lanes, masking, DAXPY, `ceil(VL/L)` scaling |
| [`simt_core`](simt_core) | GPU-style SIMT core: warps, round-robin scheduling, latency hiding, divergence stack |

Planned: chaining, SIMD packed-subword ALU (see
[`docs/roadmap.md`](../docs/roadmap.md)).
