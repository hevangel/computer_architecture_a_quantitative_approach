# Roadmap

Legend: **done** = implemented in both SystemVerilog and VHDL, self-checking testbench passing in `make test`.
**planned** = not started. Nothing is marked done unless it is in the tree and tested.

## Done (13 examples, 26 tests)

| Topic | Example |
|-------|---------|
| Ch 1 | `amdahl_speedup` |
| Ch 2 | `set_assoc_cache` |
| Ch 3 | `branch_predictor` (1-bit, 2-bit, gshare) |
| Ch 4 | `vector_lanes` |
| Ch 5 | `mesi_snoopy` |
| Ch 7 | `systolic_array` |
| App C | `rv32i_pipeline5` |
| App D | `hamming_secded`, `raid5_parity` |
| App F | `rr_crossbar` |
| App J | `carry_lookahead_adder`, `booth_multiplier`, `restoring_divider` |

## Planned, by chapter

**Ch 1 -** performance counters / CPI-breakdown unit; dynamic-power estimator from toggle counts.

**Ch 2 -** TLB with page-table walker; victim cache; stride prefetcher; hit-under-miss (non-blocking) cache;
banked DRAM controller with row buffer.

**Ch 3 / ILP -** scoreboard (CDC 6600); **Tomasulo with reorder buffer** (the book's signature example);
tournament predictor + BTB; dual-issue in-order superscalar; register renaming.

**Ch 4 -** vector chaining; SIMD packed-subword ALU; GPU SIMT warp scheduler with divergence stack.

**Ch 5 -** directory coherence; atomic RMW + spin locks; consistency litmus tests.

**Ch 6 -** Python queueing / tail-latency / PUE model (no RTL).

**Ch 7 -** convolution engine; activation + quantization stage; output-stationary variant.

**App A / C -** DLX and MIPS64 pipelines (the 1st-5th editions' ISAs); unpipelined multicycle baseline; pipelined FPU.

**App F -** mesh router with dimension-order routing and credit flow control.

**App H -** 4-slot VLIW core; software-pipelined DAXPY; predication.

**App J -** IEEE 754 adder / multiplier / FMA; SRT divider.

## Cross-cutting

* A DLX / MIPS64 variant of every ISA-dependent example, so each edition's own ISA is covered.
* Cross-language equivalence check: dump a signal trace from both simulators and `diff` them.
* CI badge and a synthesis smoke test (e.g. Yosys) for the examples that are meant to be synthesizable.
