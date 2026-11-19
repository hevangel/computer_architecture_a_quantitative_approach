# Roadmap

Legend: **done** = implemented in both SystemVerilog and VHDL, self-checking testbench passing in `make test`.
**planned** = not started. Nothing is marked done unless it is in the tree and tested.

## Implemented examples (75 examples, 150 testbenches)

| Topic | Example |
|-------|---------|
| Ch 1 | `amdahl_speedup`, `cpi_power_counters` |
| Ch 2 | `set_assoc_cache`, `tlb_walker`, `victim_cache`, `stride_prefetcher`, `stream_buffer`, `prime_probe_qos`, `alloy_dram_cache`, `cache_3c_policies`, `dram_controller`, `nonblocking_cache`, `writeback_nbcache`, `nb_set_assoc_cache`, `way_predict_vipt`, `nested_pt_walker` |
| Ch 3 | `branch_predictor` (1-bit, 2-bit, gshare), `tournament_btb_ras`, `scoreboard`, `tomasulo_rob`, `tomasulo_spec`, `tomasulo_lsq`, `spectre_transient_demo`, `tage_predictor`, `superscalar_dual_issue`, `tomasulo_mem_spec_replay`, `prf_rename_ooo`, `smt_multithread_core` |
| Ch 4 | `vector_lanes`, `vector_chaining`, `simd_alu`, `simd_pack_shuffle`, `simt_core`, `simt_coalesce_bankconflict` (core-integrated coalescing, shared replay and all-warps barrier; per-register scoreboard), `vector_bank_gather_strip` (64-element command limit) |
| Ch 5 | `mesi_snoopy`, `directory_msi`, `directory_limited_evict`, `spinlock_atomic`, `consistency_litmus_tsosb`, `llsc_backoff_barrier`, `mcs_combining_barrier`, `split_bus_transient_msi`, `moesi_false_sharing` |
| Ch 6 | `clos_ocs_fabric` |
| Ch 7 | `systolic_array`, `conv2d_linebuffer`, `systolic_os_act_quant`, `stencil_halo_2d` (single-port buffered halo and shifts), `tensor_core_sparse24_fp8` |
| App A | `rvc_compressed_decoder` (RV32C subset) |
| App C | `rv32i_pipeline5`, `mips_pipeline5` (DLX/MIPS32 and MIPS64), `multicycle_microcode_baseline`, `rv32i_precise_exceptions`, `r4000_superpipeline8` |
| App D | `hamming_secded`, `raid5_parity`, `raid6_p_q_chipkill`, `dma_split_bus_coherence` |
| App E | `dsp_qmac_circular_zoloop` |
| App F | `rr_crossbar`, `mesh_router`, `vc_router`, `torus_dateline`, `omega_fat_tree_islip`, `west_first_adaptive_spec_vc` |
| App H | `vliw4`, `vliw4_swpipe_pred_alat` |
| App J | `carry_lookahead_adder`, `booth_multiplier`, `restoring_divider`, `csa_wallace_skip_select`, `ieee754_fpu_fma_bf16`, `srt4_divider_fdiv` |

The [edition acceptance plan](../review/edition-acceptance.md) records the remaining design and verification work.

## Planned, by chapter

**Ch 1 -** [Python quantitative models](../ch01_fundamentals/python/README.md) cover
yield, chiplet cost and break-even density, reliability, DVFS, carbon and benchmark means. The
[CPI and power counters](../ch01_fundamentals/cpi_power_counters) have passed
their targeted tests in both languages.

**Ch 2 / App L -** the two-way non-blocking cache and victim forwarding have cycle-model and four-MSHR tests. The VIPT example checks safe page-offset indexing; page coloring for larger indexes and realistic memory banking remain. A source-verified MAP-I predictor;
permissions, multiple outstanding nested walks and targeted TLB shootdowns. The [nested walker](../ch02_memory_hierarchy/nested_pt_walker/README.md) handles two levels, a page-walk cache, superpages and ASIDs.

**Ch 3 / ILP -** a history-table predictor in `tomasulo_spec`; dependency-directed replay and variable-latency memory for `tomasulo_mem_spec_replay`;
complete RV32I decoding and exceptions for the dual-issue core; memory, fetch and precise exceptions for the [physical-register engine](../ch03_ilp/prf_rename_ooo/README.md); streaming instruction and memory interfaces for [multithreading](../ch03_ilp/smt_multithread_core/README.md); richer transient-execution models; ILP limit studies.

**Ch 4 -** [Python roofline and affine loop models](../ch04_dlp/python/README.md) cover a
rectangular affine nests, dependence kinds and idealized ceilings. Triangular or nonlinear loop analysis and a multi-engine out-of-order memory endpoint for `simt_core` remain planned. The asynchronous core tracks multiple pending load destinations per warp and its wrapper queues requests to a single engine; its shared-memory barrier requires all warps to participate. The vector bank/gather example currently limits commands to 64 elements.

**Ch 5 / App I -** transient-state and network timing extensions for directory coherence;
non-atomic MOESI; split-bus coherence with multiple lines and independently returning data.

**Ch 6 -** The [Python model suite](../ch06_wsc/README.md) covers PUE, simple costs, carbon,
transfer time, financed monthly costs, the 4M operational-carbon factors and a two-server FIFO simulation of hedged and tied requests. Multi-tier queueing remains planned; the Python tests are separate from `make test`.

**Ch 7 -** physical timing and pipelining for the sparse tensor model, plus finite-port stencil buffering.

**App A / K -** The [Python ISA traffic models](../appA_isa/python/README.md) compare
four synthetic ISA classes and encoded RV32IM and classic MIPS64 subsets. The
compressed decoder implements a tested RV32C subset; full compressed ISA support,
pipeline integration and textbook-specific comparisons remain planned.

**App C -** full privileged trap semantics, physical cache tags for the eight-stage core and a pipelined FPU.

**App D -** [Python queueing and rebuild-window models](../appD_storage/python/README.md)
cover Little's Law, M/M/1, M/G/1, M/M/m and independent failures during a fixed
rebuild, plus a repairable-array MTTDL model. RAID-6, educational single-symbol correction, and a simple snooped DMA model are tested.

**App E -** extend the tested DSP datapath with autonomous FIR control and programmable FFT sizing.

**App F -** multi-flit adaptive VC reservations and physical link timing.

**App H -** delayed branches and more complete speculative-instruction recovery.

**App J -** [Carry-skip, carry-select and carry-save arithmetic](../appJ_arithmetic/csa_wallace_skip_select)
has passed its targeted tests in both languages. The [binary32 arithmetic example](../appJ_arithmetic/ieee754_fpu_fma_bf16/README.md) covers add, multiply and FMA with scaled low-precision inputs. The [SRT example](../appJ_arithmetic/srt4_divider_fdiv/README.md) models the five omitted cells. A bit-exact historical implementation and synthesis measurements remain open.

## Cross-cutting

* A DLX / MIPS64 variant of every other ISA-dependent example (the pipeline is done), so each edition's own ISA is covered.
* Cross-language equivalence check: dump a signal trace from both simulators and `diff` them.
* CI badge and a synthesis smoke test (e.g. Yosys) for the examples that are meant to be synthesizable.
