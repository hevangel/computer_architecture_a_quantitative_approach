# Roadmap

Legend: **done** = implemented in both SystemVerilog and VHDL, self-checking testbench passing in `make test`.
**planned** = not started. Nothing is marked done unless it is in the tree and tested.

## Done (32 examples, 64 tests)

| Topic | Example |
|-------|---------|
| Ch 1 | `amdahl_speedup` |
| Ch 2 | `set_assoc_cache`, `tlb_walker`, `victim_cache`, `stride_prefetcher`, `dram_controller`, `nonblocking_cache`, `writeback_nbcache` |
| Ch 3 | `branch_predictor` (1-bit, 2-bit, gshare), `scoreboard`, `tomasulo_rob`, `tomasulo_spec`, `tomasulo_lsq` |
| Ch 4 | `vector_lanes`, `vector_chaining`, `simd_alu`, `simt_core` |
| Ch 5 | `mesi_snoopy`, `directory_msi` |
| Ch 7 | `systolic_array` |
| App C | `rv32i_pipeline5`, `mips_pipeline5` (DLX/MIPS32 and MIPS64) |
| App D | `hamming_secded`, `raid5_parity` |
| App F | `rr_crossbar`, `mesh_router`, `vc_router`, `torus_dateline` |
| App H | `vliw4` |
| App J | `carry_lookahead_adder`, `booth_multiplier`, `restoring_divider` |

## Planned, by chapter

**Ch 1 -** performance counters / CPI-breakdown unit; dynamic-power estimator from toggle counts.

**Ch 2 -** a separate prefetch stream buffer; store forwarding from the write / write-back buffers; set-associative non-blocking caches.

**Ch 3 / ILP -** a history-table predictor in `tomasulo_spec`; memory dependence speculation (loads bypassing unknown store addresses) in `tomasulo_lsq`; resolve-time (rather than commit-time) recovery;
tournament predictor + BTB; dual-issue in-order superscalar.

**Ch 4 -** pack/unpack and shuffle for `simd_alu`; per-register scoreboard and coalescing for `simt_core`.

**Ch 5 -** atomic RMW + spin locks; consistency litmus tests; replacements and limited-pointer sharing for `directory_msi`.

**Ch 6 -** Python queueing / tail-latency / PUE model (no RTL).

**Ch 7 -** convolution engine; activation + quantization stage; output-stationary variant.

**App A / C -** unpipelined multicycle baseline for the pipeline speedup comparison; pipelined FPU; delayed-branch variant of `mips_pipeline5`.

**App F -** adaptive (west-first) routing; speculative single-cycle VA+SA.

**App H -** software-pipelined DAXPY, predication, delayed branches for `vliw4`.

**App J -** IEEE 754 adder / multiplier / FMA; SRT divider.

## Cross-cutting

* A DLX / MIPS64 variant of every other ISA-dependent example (the pipeline is done), so each edition's own ISA is covered.
* Cross-language equivalence check: dump a signal trace from both simulators and `diff` them.
* CI badge and a synthesis smoke test (e.g. Yosys) for the examples that are meant to be synthesizable.
