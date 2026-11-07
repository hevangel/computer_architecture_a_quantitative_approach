# Roadmap

Legend: **done** = implemented in both SystemVerilog and VHDL, self-checking testbench passing in `make test`.
**planned** = not started. Nothing is marked done unless it is in the tree and tested.

## Done (25 examples, 50 tests)

| Topic | Example |
|-------|---------|
| Ch 1 | `amdahl_speedup` |
| Ch 2 | `set_assoc_cache`, `tlb_walker`, `victim_cache`, `stride_prefetcher`, `dram_controller` |
| Ch 3 | `branch_predictor` (1-bit, 2-bit, gshare), `scoreboard`, `tomasulo_rob`, `tomasulo_spec` |
| Ch 4 | `vector_lanes`, `simd_alu`, `simt_core` |
| Ch 5 | `mesi_snoopy` |
| Ch 7 | `systolic_array` |
| App C | `rv32i_pipeline5`, `mips_pipeline5` (DLX/MIPS32 and MIPS64) |
| App D | `hamming_secded`, `raid5_parity` |
| App F | `rr_crossbar`, `mesh_router` |
| App H | `vliw4` |
| App J | `carry_lookahead_adder`, `booth_multiplier`, `restoring_divider` |

## Planned, by chapter

**Ch 1 -** performance counters / CPI-breakdown unit; dynamic-power estimator from toggle counts.

**Ch 2 -** hit-under-miss (non-blocking) cache; write buffer; a separate prefetch stream buffer.

**Ch 3 / ILP -** load/store with a store buffer and a history-table predictor in `tomasulo_spec`; resolve-time (rather than commit-time) recovery;
tournament predictor + BTB; dual-issue in-order superscalar.

**Ch 4 -** vector chaining; pack/unpack and shuffle for `simd_alu`; per-register scoreboard and coalescing for `simt_core`.

**Ch 5 -** directory coherence; atomic RMW + spin locks; consistency litmus tests.

**Ch 6 -** Python queueing / tail-latency / PUE model (no RTL).

**Ch 7 -** convolution engine; activation + quantization stage; output-stationary variant.

**App A / C -** unpipelined multicycle baseline for the pipeline speedup comparison; pipelined FPU; delayed-branch variant of `mips_pipeline5`.

**App F -** virtual channels for `mesh_router`; torus with dateline routing; adaptive (west-first) routing.

**App H -** software-pipelined DAXPY, predication, delayed branches for `vliw4`.

**App J -** IEEE 754 adder / multiplier / FMA; SRT divider.

## Cross-cutting

* A DLX / MIPS64 variant of every other ISA-dependent example (the pipeline is done), so each edition's own ISA is covered.
* Cross-language equivalence check: dump a signal trace from both simulators and `diff` them.
* CI badge and a synthesis smoke test (e.g. Yosys) for the examples that are meant to be synthesizable.
