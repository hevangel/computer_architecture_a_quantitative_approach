# Computer Architecture: A Quantitative Approach -- in SystemVerilog and VHDL

Hardware implementations of the worked examples from Hennessy & Patterson's *Computer Architecture: A
Quantitative Approach*, from the 1st (1990) to the 7th (2025) edition. Every example is written **twice**,
in SystemVerilog and in VHDL, has a self-checking testbench in each language, and comes with a textbook-style
write-up (background, design, verification, exercises).

The goal is a book you can run: change a parameter, rerun the testbench, and watch the quantity the chapter
talks about -- a CPI, a miss rate, a speedup -- move.

## Quick start

Open [the browser index](index.html) for chapter navigation and links to every example's guide,
SystemVerilog sources and VHDL sources. The index works without JavaScript and can be opened locally.
Its editable content lives in `data/index.json`; after changing it, regenerate with
`node scripts/render-index.mjs` and verify with `node scripts/render-index.mjs --check` (Node.js 22+).

Requires Python 3, [Icarus Verilog](https://github.com/steveicarus/iverilog) 12 (SystemVerilog), [GHDL](https://github.com/ghdl/ghdl) 4.x (VHDL),
and optionally [Verilator](https://www.veripool.org/verilator/) 5 (lint). On Ubuntu 24.04:

```bash
sudo apt-get install -y iverilog ghdl verilator
```

```bash
make test                    # run every example in both languages
make test T=cache            # only modules whose path contains "cache"
make test-sv                 # SystemVerilog only (also: make test-vhdl)
make list                    # list what was discovered
make lint                    # advisory Verilator lint of the SystemVerilog
```

The current tree contains 75 hardware examples. The complete suite passed `150/150` using Icarus Verilog 14.0 development and GHDL 6.0.0. The final eight-stage delay-slot interlock change also passed targeted runs in both languages. The
[CPI counters](ch01_fundamentals/cpi_power_counters/README.md) and
[arithmetic blocks](appJ_arithmetic/csa_wallace_skip_select/README.md) also passed targeted simulations.

The [quantitative fundamentals](ch01_fundamentals/python/README.md),
[roofline and loop dependence](ch04_dlp/python/README.md), [warehouse-scale](ch06_wsc/README.md)
and [I/O queueing](appD_storage/python/README.md) Python models have separate unittest commands
and are not included in that HDL test count. The [ISA class traffic models](appA_isa/python/README.md)
likewise compare synthetic instruction sets separately from the HDL examples.

## What is in the box

| Chapter / appendix | Example | Shows |
|--------------------|---------|-------|
| [Ch 1 Fundamentals](ch01_fundamentals) | [`amdahl_speedup`](ch01_fundamentals/amdahl_speedup) | Amdahl's Law in fixed point |
| | [`cpi_power_counters`](ch01_fundamentals/cpi_power_counters) | CPI, stall and energy counters |
| [Ch 2 Memory hierarchy](ch02_memory_hierarchy) | [`set_assoc_cache`](ch02_memory_hierarchy/set_assoc_cache) | set-associative write-back LRU cache with hit/miss counters |
| | [`tlb_walker`](ch02_memory_hierarchy/tlb_walker) | TLB + page-table walker, page and protection faults |
| | [`victim_cache`](ch02_memory_hierarchy/victim_cache) | victim buffer turns thrashing conflict misses into swaps (random trace -33 % cycles) |
| | [`stride_prefetcher`](ch02_memory_hierarchy/stride_prefetcher) | stride prefetcher (misses 48 -> 3 on a strided walk); loses when there is no idle time |
| | [`stream_buffer`](ch02_memory_hierarchy/stream_buffer) | four-entry sequential prefetch buffer; demand and speculative read counts |
| | [`prime_probe_qos`](ch02_memory_hierarchy/prime_probe_qos) | shared-cache replacement channel and way partitioning |
| | [`cache_3c_policies`](ch02_memory_hierarchy/cache_3c_policies) | 3C miss classification with LRU, FIFO, random and pseudo-LRU |
| | [`alloy_dram_cache`](ch02_memory_hierarchy/alloy_dram_cache) | direct-mapped tag/data cache and illustrative miss prediction |
| | [`nonblocking_cache`](ch02_memory_hierarchy/nonblocking_cache) | non-blocking write-through cache: MSHRs, hit/miss under miss (2157 -> 1881 -> 674 cycles), coalescing write buffer |
| | [`nested_pt_walker`](ch02_memory_hierarchy/nested_pt_walker) | nested translation, page-walk cache, superpages and ASID TLB |
| | [`way_predict_vipt`](ch02_memory_hierarchy/way_predict_vipt) | VIPT way prediction and critical-word-first refill |
| | [`nb_set_assoc_cache`](ch02_memory_hierarchy/nb_set_assoc_cache) | two-way non-blocking cache and buffered-victim forwarding, checked against a cycle model |
| | [`writeback_nbcache`](ch02_memory_hierarchy/writeback_nbcache) | write-back / write-allocate non-blocking cache: dirty bits, write-back buffer, 125 stores -> 34 line writes |
| | [`dram_controller`](ch02_memory_hierarchy/dram_controller) | banked DRAM controller: row-buffer hit/miss/conflict = 9/12/15 cycles, FR-FCFS (2 ACT) vs FCFS (8 ACT), refresh, streaming at 96 % of peak |
| [Ch 3 ILP](ch03_ilp) | [`branch_predictor`](ch03_ilp/branch_predictor) | 1-bit, 2-bit and gshare prediction (32 / 23 / 17 mispredicts of 60) |
| | [`tage_predictor`](ch03_ilp/tage_predictor) | geometric tagged histories, usefulness and gshare baseline |
| | [`spectre_transient_demo`](ch03_ilp/spectre_transient_demo) | speculative cache footprint and delaying mitigation |
| | [`tournament_btb_ras`](ch03_ilp/tournament_btb_ras) | local/global tournament prediction, target buffer and return stack |
| | [`scoreboard`](ch03_ilp/scoreboard) | CDC 6600 scoreboard: the four hazards as exact stall cycles |
| | [`smt_multithread_core`](ch03_ilp/smt_multithread_core) | two-thread renaming and shared dual-issue scheduling |
| | [`prf_rename_ooo`](ch03_ilp/prf_rename_ooo) | physical register renaming, free-list conservation and branch recovery |
| | [`tomasulo_mem_spec_replay`](ch03_ilp/tomasulo_mem_spec_replay) | speculative loads, replay and resolve-time branch recovery |
| | [`superscalar_dual_issue`](ch03_ilp/superscalar_dual_issue) | two-wide in-order RV32I subset with forwarding and issue checks |
| | [`tomasulo_spec`](ch03_ilp/tomasulo_spec) | Tomasulo + branch speculation: commit-time flush, loop 85 -> 76 cycles with a better predictor |
| | [`tomasulo_lsq`](ch03_ilp/tomasulo_lsq) | speculative Tomasulo + load/store queue: stores write at commit, store-to-load forwarding (8 vs 11 cycles), conservative disambiguation, wrong-path store never reaches memory |
| | [`tomasulo_rob`](ch03_ilp/tomasulo_rob) | Tomasulo + reorder buffer: out-of-order completion, in-order commit, renaming |
| [Ch 4 DLP](ch04_dlp) | [`vector_lanes`](ch04_dlp/vector_lanes) | vector unit, DAXPY, `ceil(VL/lanes)` scaling |
| | [`vector_bank_gather_strip`](ch04_dlp/vector_bank_gather_strip) | bank conflicts and strip-mined gather/scatter |
| | [`vector_chaining`](ch04_dlp/vector_chaining) | pipelined vector units + chaining: DAXPY idle at cycle 49 chained vs 79 unchained (3 convoys x 16) |
| | [`simd_alu`](ch04_dlp/simd_alu) | 64-bit packed SIMD ALU (partitioned adder, saturating ops, PMADD, PSAD); 8 instructions for 64 pixels |
| | [`simd_pack_shuffle`](ch04_dlp/simd_pack_shuffle) | saturating packing, signed/zero extension, byte/halfword shuffle and transpose |
| | [`simt_core`](ch04_dlp/simt_core) | GPU SIMT core: warps hide load latency (54 vs 72 cycles), divergence costs lane efficiency (0.77) |
| | [`simt_coalesce_bankconflict`](ch04_dlp/simt_coalesce_bankconflict) | standalone SIMT memory counts, scoreboards and barrier |
| [Ch 5 TLP](ch05_tlp) | [`mesi_snoopy`](ch05_tlp/mesi_snoopy) | MESI snooping coherence, invariants under random traffic |
| | [`directory_limited_evict`](ch05_tlp/directory_limited_evict) | directory replacement and sharer representation tradeoffs |
| | [`split_bus_transient_msi`](ch05_tlp/split_bus_transient_msi) | delayed data responses and ordered MSI upgrade races |
| | [`moesi_false_sharing`](ch05_tlp/moesi_false_sharing) | Owned dirty data forwarding and word-level sharing classification |
| | [`mcs_combining_barrier`](ch05_tlp/mcs_combining_barrier) | MCS and centralized lock handoff with tree and centralized barrier traffic |
| | [`llsc_backoff_barrier`](ch05_tlp/llsc_backoff_barrier) | LR/SC reservations, TTAS backoff and a reusable barrier |
| | [`consistency_litmus_tsosb`](ch05_tlp/consistency_litmus_tsosb) | SC versus buffered TSO, forwarding and fences |
| | [`spinlock_atomic`](ch05_tlp/spinlock_atomic) | spin locks on a snooping bus: TAS vs TTAS vs ticket (FIFO), hand-derived 33/45-cycle two-core runs, transactions per acquisition at 2/4/8 cores |
| | [`directory_msi`](ch05_tlp/directory_msi) | directory MSI: sharer vectors, 2/4-hop transactions, 2k+2 messages for a write to k sharers; 4.1 messages per miss at 16 nodes vs a 15-way broadcast |
| [Ch 6 WSC](ch06_wsc) | [`clos_ocs_fabric`](ch06_wsc/clos_ocs_fabric) | fixed and reconfigured leaf-to-spine paths |
| [Ch 7 DSA](ch07_dsa) | [`systolic_array`](ch07_dsa/systolic_array) | TPU-style weight-stationary matrix unit |
| | [`tensor_core_sparse24_fp8`](ch07_dsa/tensor_core_sparse24_fp8) | 4×4 dense and 2:4 sparse BF16/FP8 accumulation |
| | [`conv2d_linebuffer`](ch07_dsa/conv2d_linebuffer) | streaming signed 3×3 convolution |
| | [`stencil_halo_2d`](ch07_dsa/stencil_halo_2d) | scratchpad Sobel and box stencil |
| | [`systolic_os_act_quant`](ch07_dsa/systolic_os_act_quant) | output-stationary matrix unit, activation and int8 narrowing |
| [App A ISA](appA_isa) | [`rvc_compressed_decoder`](appA_isa/rvc_compressed_decoder) | RV32C subset expansion and mixed-width fetch |
| [App C Pipelining](appC_pipelining) | [`multicycle_microcode_baseline`](appC_pipelining/multicycle_microcode_baseline) | hardwired and microcoded RV32I with pipeline comparison |
| | [`r4000_superpipeline8`](appC_pipelining/r4000_superpipeline8) | eight-stage MIPS64 pipeline, load-use and branch penalties |
| | [`rv32i_precise_exceptions`](appC_pipelining/rv32i_precise_exceptions) | in-order retirement, age-ordered traps and MRET |
| | [`rv32i_pipeline5`](appC_pipelining/rv32i_pipeline5) | RISC-V 5-stage pipeline (branches in EX); CPI = 78/49 |
| | [`mips_pipeline5`](appC_pipelining/mips_pipeline5) | DLX / MIPS32 and MIPS64 5-stage pipeline (branches in ID); CPI = 84/53 |
| [App E Embedded](appE_embedded) | [`dsp_qmac_circular_zoloop`](appE_embedded/dsp_qmac_circular_zoloop) | DSP MAC, circular addressing and repeat |
| [App D Storage](appD_storage) | [`hamming_secded`](appD_storage/hamming_secded), [`raid5_parity`](appD_storage/raid5_parity), [`raid6_p_q_chipkill`](appD_storage/raid6_p_q_chipkill), [`dma_split_bus_coherence`](appD_storage/dma_split_bus_coherence) | ECC, RAID rebuild, symbol correction and DMA coherence |
| [App F Interconnect](appF_interconnect) | [`rr_crossbar`](appF_interconnect/rr_crossbar) | crossbar with round-robin arbitration |
| | [`mesh_router`](appF_interconnect/mesh_router) | wormhole mesh router + 4x4 mesh: XY routing, credits (FIFO depth 4 = the 4-cycle credit loop), zero-load latency `2(hops+1)+flits-1` |
| | [`vc_router`](appF_interconnect/vc_router) | virtual-channel router: VC + switch allocation, per-VC credits; removes head-of-line blocking (short packet done at cycle 13 vs 93); 2 VC x 4 beats 1 VC x 8 under load |
| | [`west_first_adaptive_spec_vc`](appF_interconnect/west_first_adaptive_spec_vc) | adaptive 4×4 mesh with speculative allocation |
| | [`omega_fat_tree_islip`](appF_interconnect/omega_fat_tree_islip) | Omega blocking and iterative crossbar arbitration |
| | [`torus_dateline`](appF_interconnect/torus_dateline) | 4x4 torus: shorter-way-round routing, dateline VC classes; the ring and shift traffic deadlock with 1 VC and complete with 2; hops 2.01 vs 2.59 on a mesh |
| [App H VLIW](appH_vliw) | [`vliw4_swpipe_pred_alat`](appH_vliw/vliw4_swpipe_pred_alat) | modulo-scheduled DAXPY, predicates, NaT and advanced-load checks |
| | [`vliw4`](appH_vliw/vliw4) | 4-slot VLIW, exposed pipeline; same kernel at IPC 1.01 / 1.77 / 1.94 by schedule |
| [App J Arithmetic](appJ_arithmetic) | [`carry_lookahead_adder`](appJ_arithmetic/carry_lookahead_adder), [`booth_multiplier`](appJ_arithmetic/booth_multiplier), [`restoring_divider`](appJ_arithmetic/restoring_divider) | adder, multiplier, divider |
| | [`srt4_divider_fdiv`](appJ_arithmetic/srt4_divider_fdiv) | radix-4 SRT and five-cell selection fault |
| | [`ieee754_fpu_fma_bf16`](appJ_arithmetic/ieee754_fpu_fma_bf16) | binary32 arithmetic and scaled BF16/FP8 FMA |
| | [`csa_wallace_skip_select`](appJ_arithmetic/csa_wallace_skip_select) | carry-skip / select adders and carry-save multiplier |

Not yet written (adaptive routing, ...):
see the [roadmap](docs/roadmap.md). Chapter 6 (warehouse-scale computers) is a modelling chapter with no RTL.

## Organization

Examples are organized by **topic**, not by edition, because most subjects (pipelines, caches, predictors) recur
in every edition. [`docs/editions.md`](docs/editions.md) compares the seven editions and maps each topic to the
editions that cover it and the ISA each used (DLX, MIPS64, RISC-V).

```
chNN_topic/ | appX_topic/
    README.md                 chapter introduction + example index
    example_name/
        README.md             the textbook-style write-up
        deps.txt              (optional) other examples whose RTL this one reuses
        sv/   *.sv  tb_*.sv   RTL + one self-checking testbench
        vhdl/ *.vhd tb_*.vhd  the same design and the same test in VHDL
scripts/run_tests.py          discovers examples, runs both languages
docs/                         edition guide, roadmap
```

Every testbench prints `TEST PASSED` or `TEST FAILED` and the runner checks the exit code too. The SystemVerilog
and VHDL versions of a test use the same stimulus and expectations (random streams use the same LCG), and
where the design is deterministic they finish at the same simulated time, which is a handy cross-language check.

## Adding an example

1. Create `chNN_topic/new_example/{sv,vhdl}/` with RTL and a `tb_<name>` testbench in each language.
2. The testbench must be self-checking, print `TEST PASSED` on success, and end the simulation itself.
3. Write `README.md` in the same shape as the existing ones; list it in the chapter README, in
   [`docs/editions.md`](docs/editions.md) and in [`docs/roadmap.md`](docs/roadmap.md).
4. `make test T=new_example` must pass in both languages. See [`CLAUDE.md`](CLAUDE.md) for tool quirks.
