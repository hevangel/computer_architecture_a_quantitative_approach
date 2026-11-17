# Roadmap

Legend: **done** = implemented in both SystemVerilog and VHDL, self-checking testbench passing in `make test`.
**planned** = not started. Nothing is marked done unless it is in the tree and tested.

## Done (38 examples, 76 tests)

| Topic | Example |
|-------|---------|
| Ch 1 | `amdahl_speedup`, `cpi_power_counters` |
| Ch 2 | `set_assoc_cache`, `tlb_walker`, `victim_cache`, `stride_prefetcher`, `stream_buffer`, `prime_probe_qos`, `dram_controller`, `nonblocking_cache`, `writeback_nbcache` |
| Ch 3 | `branch_predictor` (1-bit, 2-bit, gshare), `tournament_btb_ras`, `scoreboard`, `tomasulo_rob`, `tomasulo_spec`, `tomasulo_lsq` |
| Ch 4 | `vector_lanes`, `vector_chaining`, `simd_alu`, `simt_core` |
| Ch 5 | `mesi_snoopy`, `directory_msi`, `spinlock_atomic` |
| Ch 7 | `systolic_array` |
| App C | `rv32i_pipeline5`, `mips_pipeline5` (DLX/MIPS32 and MIPS64) |
| App D | `hamming_secded`, `raid5_parity` |
| App F | `rr_crossbar`, `mesh_router`, `vc_router`, `torus_dateline` |
| App H | `vliw4` |
| App J | `carry_lookahead_adder`, `booth_multiplier`, `restoring_divider`, `csa_wallace_skip_select` |

## Planned, by chapter

**Ch 1 -** [Python quantitative models](../ch01_fundamentals/python/README.md) cover
yield, chiplet cost, reliability, DVFS, carbon and benchmark means. The
[CPI and power counters](../ch01_fundamentals/cpi_power_counters) have passed
their targeted tests in both languages.

**Ch 2 / App L -** set-associative non-blocking caches with write-buffer forwarding;
3C classification and replacement; way prediction and VIPT; Alloy DRAM cache;
nested page walks, page-walk caches, superpages and address-space tags.

**Ch 3 / ILP -** a history-table predictor in `tomasulo_spec`; memory dependence speculation (loads bypassing unknown store addresses) in `tomasulo_lsq`; resolve-time (rather than commit-time) recovery;
TAGE; dual-issue in-order superscalar; physical-register
renaming; multithreading; transient-execution leakage and mitigation; ILP limit studies.

**Ch 4 -** [Python roofline and affine loop models](../ch04_dlp/python/README.md) cover a
single loop and idealized ceilings. Nested-loop analysis, pack/unpack and shuffle for
`simd_alu`, per-register scoreboard and coalescing for `simt_core`, shared-memory bank conflicts,
and vector bank conflicts, gather/scatter and strip-mining remain planned.

**Ch 5 / App I -** consistency litmus tests; LL/SC and back-off locks; sense-reversing and
combining-tree barriers; MCS locks; replacements and limited-pointer sharing for `directory_msi`;
MOESI and false sharing; split-bus transient coherence and races.

**Ch 6 -** The [Python model suite](../ch06_wsc/README.md) covers PUE, simple costs, carbon,
transfer time, fan-out with delayed hedging and a two-server FIFO simulation of hedged and tied requests. A complete 4M model and
the Clos/OCS RTL fabric remain planned; the Python tests are separate from `make test`.

**Ch 7 -** convolution engine; activation + quantization stage; output-stationary variant;
sparse tensor MMA and lower-precision arithmetic; stencil and halo exchange.

**App A / K -** The [Python ISA traffic models](../appA_isa/python/README.md) compare
four synthetic ISA classes and encoded RV32IM and classic MIPS64 subsets. Textbook-specific
comparisons and compressed RISC-V decoding remain planned.

**App C -** hardwired and microcoded multicycle baseline; precise exceptions; R4000-style
superpipeline; pipelined FPU; delayed-branch variant of `mips_pipeline5`.

**App D -** [Python queueing and rebuild-window models](../appD_storage/python/README.md)
cover Little's Law, M/M/1, M/G/1, M/M/m and independent failures during a fixed
rebuild, plus a repairable-array MTTDL model. RAID-6 and Chipkill RTL, and DMA coherence remain planned.

**App E -** fixed-point DSP MAC, circular and bit-reversed addressing, zero-overhead loops.

**App F -** adaptive (west-first) routing; speculative single-cycle VA+SA; Omega network and iterative iSLIP arbitration.

**App H -** software-pipelined DAXPY, predication, delayed branches for `vliw4`.

**App J -** [Carry-skip, carry-select and carry-save arithmetic](../appJ_arithmetic/csa_wallace_skip_select)
has passed its targeted tests in both languages. IEEE 754 adder /
multiplier / FMA and radix-4 SRT divider with fault injection remain planned.

## Cross-cutting

* A DLX / MIPS64 variant of every other ISA-dependent example (the pipeline is done), so each edition's own ISA is covered.
* Cross-language equivalence check: dump a signal trace from both simulators and `diff` them.
* CI badge and a synthesis smoke test (e.g. Yosys) for the examples that are meant to be synthesizable.
