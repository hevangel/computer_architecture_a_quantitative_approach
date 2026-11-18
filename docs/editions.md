# The seven editions at a glance

*Computer Architecture: A Quantitative Approach* (Hennessy & Patterson; Kozyrakis joins as a coauthor
on the 7th edition) has been revised six times since 1990. The editions are best read as a record of
which techniques paid off best in each era, not as ever-larger versions of the same book.

> **Accuracy note.** The edition summaries below come from the project background notes (publisher
> tables of contents and edition descriptions). Chapter and appendix *numbers* differ between editions
> and between print and online material, so this repository names directories by **topic**
> (`ch03_ilp`, `appC_pipelining`, ...) using the 6th/7th-edition chapter numbers for the main text and
> the 5th-edition appendix letters. When in doubt, check your own copy.

## 1. What changed in each edition

| Ed. | Year | Emphasis | Teaching ISA |
|-----|------|----------|--------------|
| 1st | 1990 | Establishes the *quantitative* method: benchmarks, execution time, Amdahl's Law, cost; RISC, pipelining, memory hierarchy | DLX |
| 2nd | 1995-96 | Superscalar issue, dynamic scheduling, branch prediction, multiprocessors, interconnection networks, storage | DLX |
| 3rd | 2002 | Hardware vs. compiler ILP split into two chapters (Tomasulo/speculation vs. VLIW/EPIC and Itanium); basic pipelining moves to an appendix | MIPS64 |
| 4th | 2006 | The end of the frequency race: power and energy become first-class constraints; multicore and thread-level parallelism move forward | MIPS64 |
| 5th | 2011 | Vector/SIMD/GPU chapter and warehouse-scale computers added; memory hierarchy moves to Chapter 2; ARM Cortex-A8 and Intel Core i7 case studies | MIPS64 |
| 6th | 2017 | Switches to RISC-V; new chapter on domain-specific architectures (TPU, Catapult, Pixel Visual Core, ...) | RISC-V |
| 7th | 2025 | Updates include chiplets and yield, embodied carbon, Alloy Cache and NUCA, side channels, TAGE, Power10 and Xeon multicore case studies, warehouse-scale networks and updated accelerators | RISC-V |

The 7th edition's case studies also discuss Meta servers, Google's Jupiter
network, AWS Nitro and Graviton3, TPU v4, NVIDIA Tensor Cores and Transformer
Engine, Graphcore IPUs, Samsung NPUs, MLPerf and sustainability. See Chapter 1
§§1.5–1.6, Chapter 2 §§2.3–2.4, Chapter 3 §§3.3 and 3.13, Chapter 5 §5.8,
and Chapters 6–7. Mention here does not imply the corresponding case study has
a runnable implementation in this repository.

The three eras:

* **1990-2002 (1st-3rd): make one processor faster.** Pipelining, superscalar, out-of-order, speculation. Ended by power and by the limits of instruction-level parallelism (ILP).
* **2006-2011 (4th-5th): get throughput from parallelism.** Multicore, vectors, GPUs; energy efficiency.
* **2017-2025 (6th-7th): optimize the whole heterogeneous system.** Domain-specific accelerators, SoCs.

These are shifts of emphasis, not hard boundaries: multiprocessors and vector machines were in the
earliest editions and ILP is still in the newest.

## 2. What happened to the older material

| Subject | Earlier editions | Later editions |
|---------|------------------|----------------|
| Basic instruction sets and pipelining | Main chapters | Review appendices |
| Out-of-order CPU design | Expanded greatly in 2nd-3rd | Still a main subject |
| VLIW and Itanium/EPIC | Prominent in 3rd-4th | Mostly supplemental appendix |
| Disk and storage architecture | Main chapters through 4th | Supplemental material |
| Traditional vector processors | Historically important | Folded into the DLP/GPU chapter; detail in an appendix |
| Multiprocessors | Expanded in 2nd-4th | Multicore and thread-level parallelism |
| GPUs | Little | Dedicated chapter from 5th |
| Data-center architecture | Clusters and networks | Warehouse-scale chapter from 5th |
| AI / domain-specific accelerators | Not central | Dedicated chapter from 6th |

## 3. Where each topic lives in this repository

An example appears **once**, under its topic, and the table says which editions treat it. Where an
edition used a different ISA the example is provided for that ISA too (or is on the [roadmap](roadmap.md)).

| Topic | Directory | Editions that cover it | Status |
|-------|-----------|------------------------|:------:|
| Amdahl's Law | [`ch01_fundamentals/amdahl_speedup`](../ch01_fundamentals/amdahl_speedup) | 1-7 | done |
| CPI, stall and switching-energy counters | [`ch01_fundamentals/cpi_power_counters`](../ch01_fundamentals/cpi_power_counters) | 7th Ch 1 §§1.5, 1.8–1.9 | done |
| Yield, cost, dependability, DVFS and benchmark summaries | [`ch01_fundamentals/python`](../ch01_fundamentals/python/README.md) | 7th Ch 1 §§1.5–1.8 | partial Python models |
| Processor control and microprogramming | [`appC_pipelining`](../appC_pipelining) | 1st Ch 5 | multicycle and microcode baseline planned |
| Physical-register renaming | [`ch03_ilp/prf_rename_ooo`](../ch03_ilp/prf_rename_ooo) | 6th Ed Ch 3 §3.8 | external issue interface; no memory or exceptions |
| Speculative loads and replay | [`ch03_ilp/tomasulo_mem_spec_replay`](../ch03_ilp/tomasulo_mem_spec_replay) | 6th Ed Ch 3 §§3.6, 3.9 | suffix recovery with one load unit |
| In-order dual issue | [`ch03_ilp/superscalar_dual_issue`](../ch03_ilp/superscalar_dual_issue) | 6th Ed Ch 3 §3.7 | tested RV32I subset; full decoding and traps remain |
| ILP limits and hardware multithreading | [`ch03_ilp/smt_multithread_core`](../ch03_ilp/smt_multithread_core) | 6th Ch 3 §3.11 | four scheduling modes; ILP-limit studies remain planned |
| Instruction set principles and ISA survey | [`appA_isa`](../appA_isa) | 1st Ch 3–4; 5th–7th App A and K | synthetic classes, RV32IM and MIPS64 subsets; partial compressed decoding |
| Compressed RV32C subset and fetch | [`appA_isa/rvc_compressed_decoder`](../appA_isa/rvc_compressed_decoder) | 6th App A and K.2 | done for listed subset; pipeline integration planned |
| Embedded systems and DSPs | [`appE_embedded`](../appE_embedded) | 5th–7th App E | fixed-point DSP datapath tested |
| Vector processors in depth | [`ch04_dlp`](../ch04_dlp) | 1st Ch 7; 5th–7th App G | bank conflicts and gather/scatter in a bounded vector memory model |
| Roofline and loop dependence | [`ch04_dlp/python`](../ch04_dlp/python/README.md) | 7th Ch 4 §§4.3–4.5, 4.7 | partial Python models |
| Large-scale multiprocessors | [`ch05_tlp`](../ch05_tlp) | 5th–7th App I | partial; transient coherence and scalable synchronization planned |
| Advanced address translation | [`ch02_memory_hierarchy/nested_pt_walker`](../ch02_memory_hierarchy/nested_pt_walker) | 6th–7th App L | serialized nested walker, superpages, page-walk cache and ASIDs; permissions and shootdowns remain |
| Historical perspectives | — | 6th–7th App M | reference material, not an RTL example |
| 5-stage pipeline, hazards, forwarding (RV32I) | [`appC_pipelining/rv32i_pipeline5`](../appC_pipelining/rv32i_pipeline5) | 6-7 ISA; the pipeline itself 1-7 | done |
| 5-stage pipeline, branches in ID (DLX = `XLEN 32`, MIPS64 = `XLEN 64`) | [`appC_pipelining/mips_pipeline5`](../appC_pipelining/mips_pipeline5) | 1-2 (DLX), 3-5 (MIPS64) | done |
| 1-bit, 2-bit, correlating (gshare) prediction | [`ch03_ilp/branch_predictor`](../ch03_ilp/branch_predictor) | 1-7 | done |
| Tournament prediction, BTB and return stack | [`ch03_ilp/tournament_btb_ras`](../ch03_ilp/tournament_btb_ras) | 7th Ch 3 §§3.3, 3.9 | done; non-speculative model |
| Cache: associativity, write-back, LRU | [`ch02_memory_hierarchy/set_assoc_cache`](../ch02_memory_hierarchy/set_assoc_cache) | 1-7 | done |
| Banked vector memory and strip-mining | [`ch04_dlp/vector_bank_gather_strip`](../ch04_dlp/vector_bank_gather_strip) | 6th Ed Ch 4 §4.2 and App G | 64-element commands |
| Vector processor / lanes, DAXPY | [`ch04_dlp/vector_lanes`](../ch04_dlp/vector_lanes) | 1-7 (main chapter from 5th) | done |
| Vector chaining, convoys and chimes | [`ch04_dlp/vector_chaining`](../ch04_dlp/vector_chaining) | 1-7 (appendix G / Ch 4) | done |
| Snooping coherence (MESI) | [`ch05_tlp/mesi_snoopy`](../ch05_tlp/mesi_snoopy) | 2-7 | done |
| SC and TSO consistency litmus tests | [`ch05_tlp/consistency_litmus_tsosb`](../ch05_tlp/consistency_litmus_tsosb) | 7th Ch 5 §5.6 | done; explicit-drain teaching model |
| Atomic RMW and spin locks (TAS, TTAS, ticket) on a snooping bus: traffic per acquisition | [`ch05_tlp/spinlock_atomic`](../ch05_tlp/spinlock_atomic) | 2-7 | done |
| Directory replacement and limited sharer tracking | [`ch05_tlp/directory_limited_evict`](../ch05_tlp/directory_limited_evict) | 6th Ed Ch 5 §5.4 | serialized model with conservative stale entries |
| Directory coherence (MSI, sharer vectors, message counts) | [`ch05_tlp/directory_msi`](../ch05_tlp/directory_msi) | 2-7 | done |
| Systolic matrix unit (TPU) | [`ch07_dsa/systolic_array`](../ch07_dsa/systolic_array) | 6-7 | done |
| Scratchpad Sobel and box stencils | [`ch07_dsa/stencil_halo_2d`](../ch07_dsa/stencil_halo_2d) | 6th Ed Ch 7 §7.7 | buffered halo and directional shifts |
| Streaming 3×3 convolution | [`ch07_dsa/conv2d_linebuffer`](../ch07_dsa/conv2d_linebuffer) | 6-7 Ch 7 §7.3 | done |
| Output-stationary matrix unit, activation and quantization | [`ch07_dsa/systolic_os_act_quant`](../ch07_dsa/systolic_os_act_quant) | 6-7 Ch 7 §§7.3–7.4 | done; fixed-point teaching model |
| Computer arithmetic: CLA, Booth, division | [`appJ_arithmetic`](../appJ_arithmetic) | 1-7 (appendix) | done |
| Binary32 and low-precision FMA | [`appJ_arithmetic/ieee754_fpu_fma_bf16`](../appJ_arithmetic/ieee754_fpu_fma_bf16) | 7th App J.3–J.7; Ch 7 | paired HDL with a shared exact Python reference |
| Carry-skip / carry-select / carry-save arithmetic | [`appJ_arithmetic/csa_wallace_skip_select`](../appJ_arithmetic/csa_wallace_skip_select) | 7th App J.8–J.9 | done |
| ECC, RAID parity, symbol correction and DMA coherence | [`appD_storage`](../appD_storage) | 1-7 (main chapter through 4th, then supplemental) | done |
| I/O queueing, rebuild-window probability and MTTDL | [`appD_storage/python`](../appD_storage/python/README.md) | 5-7 App D.4–D.5 | Python models with explicit reliability assumptions |
| Crossbar and arbitration | [`appF_interconnect/rr_crossbar`](../appF_interconnect/rr_crossbar) | 2-7 | done |
| Torus with dateline virtual-channel classes (deadlock avoidance) | [`appF_interconnect/torus_dateline`](../appF_interconnect/torus_dateline) | 2-7 (interconnect material) | done |
| Virtual channels: VC allocation, switch allocation, no head-of-line blocking | [`appF_interconnect/vc_router`](../appF_interconnect/vc_router) | 2-7 (interconnect material) | done |
| Mesh network: wormhole routing, credit flow control | [`appF_interconnect/mesh_router`](../appF_interconnect/mesh_router) | 2-7 (interconnect material) | done |
| Tomasulo + reorder buffer | [`ch03_ilp/tomasulo_rob`](../ch03_ilp/tomasulo_rob) | dynamic scheduling 2-7; ROB form from the 3rd | done |
| Speculation and cache side effects | [`ch03_ilp/spectre_transient_demo`](../ch03_ilp/spectre_transient_demo) | 7th Ed Ch 3 §3.13 | abstract timing model, not a real exploit |
| Tagged-history branch prediction | [`ch03_ilp/tage_predictor`](../ch03_ilp/tage_predictor) | 6th Ed Ch 3 §3.3 | small non-speculative teaching model |
| LR/SC and synchronization | [`ch05_tlp/llsc_backoff_barrier`](../ch05_tlp/llsc_backoff_barrier) | 6th Ed Ch 5 §5.5 and App I §I.4 | serialized reservation monitor and snooping-bus lock model |
| CDC 6600 scoreboard | [`ch03_ilp/scoreboard`](../ch03_ilp/scoreboard) | 2-7 (the early editions' dynamic-scheduling intro) | done |
| Hardware speculation (Tomasulo + ROB past branches) | [`ch03_ilp/tomasulo_spec`](../ch03_ilp/tomasulo_spec) | ROB form from the 3rd | done |
| Load/store queue: memory disambiguation, store-to-load forwarding, stores at commit | [`ch03_ilp/tomasulo_lsq`](../ch03_ilp/tomasulo_lsq) | ROB form from the 3rd | done |
| VLIW (static multiple issue, exposed latencies) | [`appH_vliw/vliw4`](../appH_vliw/vliw4) | 3-4 main, later appendix | done |
| SIMD multimedia extensions (packed subwords, saturation, PMADD, PSAD) | [`ch04_dlp/simd_alu`](../ch04_dlp/simd_alu) | 5-7 (main chapter) | done |
| SIMD narrowing, extension and shuffle | [`ch04_dlp/simd_pack_shuffle`](../ch04_dlp/simd_pack_shuffle) | 7th Ch 4 §4.3 | done; standalone datapath |
| SIMT coalescing, bank replay and scoreboard | [`ch04_dlp/simt_coalesce_bankconflict`](../ch04_dlp/simt_coalesce_bankconflict) | 6th Ed Ch 4 §4.4 | global coalescing, shared replay, all-warps barrier and per-register scoreboard in core; wrapper queues requests to one memory engine |
| GPU SIMT core: warps, latency hiding, divergence | [`ch04_dlp/simt_core`](../ch04_dlp/simt_core) | 5-7 | done |
| TLB, page-table walker, protection | [`ch02_memory_hierarchy/tlb_walker`](../ch02_memory_hierarchy/tlb_walker) | 1-7 | done |
| Cache miss classification and policies | [`ch02_memory_hierarchy/cache_3c_policies`](../ch02_memory_hierarchy/cache_3c_policies) | 6th Ed App B §B.3 | finite block space; conflict includes replacement-policy effects |
| Victim cache | [`ch02_memory_hierarchy/victim_cache`](../ch02_memory_hierarchy/victim_cache) | cache-optimization material (placement varies) | done |
| Hardware stride prefetching | [`ch02_memory_hierarchy/stride_prefetcher`](../ch02_memory_hierarchy/stride_prefetcher) | cache-optimization material (placement varies) | done |
| Sequential stream buffer | [`ch02_memory_hierarchy/stream_buffer`](../ch02_memory_hierarchy/stream_buffer) | 7th Ch 2 §2.3 | done; idealized memory |
| Cache timing and way partitioning | [`ch02_memory_hierarchy/prime_probe_qos`](../ch02_memory_hierarchy/prime_probe_qos) | 7th Ch 2 §2.4 | done; single-set model |
| Direct-mapped DRAM cache and miss prediction | [`ch02_memory_hierarchy/alloy_dram_cache`](../ch02_memory_hierarchy/alloy_dram_cache) | 7th Ch 2 §2.3, exercise 2.29 | done; illustrative predictor, not verified MAP-I |
| Banked DRAM controller: row buffers, FR-FCFS, refresh | [`ch02_memory_hierarchy/dram_controller`](../ch02_memory_hierarchy/dram_controller) | 2-7 | done |
| VIPT way prediction and critical-word-first refill | [`ch02_memory_hierarchy/way_predict_vipt`](../ch02_memory_hierarchy/way_predict_vipt) | 6th Ed Ch 2 §2.3 | safe index configurations; fixed-latency internal backing memory |
| Two-way non-blocking write-back and victim forwarding | [`ch02_memory_hierarchy/nb_set_assoc_cache`](../ch02_memory_hierarchy/nb_set_assoc_cache) | 6th Ed Ch 2 §2.3 | directed, shadow-memory and independent cycle-model tests pass |
| Write-back / write-allocate non-blocking cache, dirty bits, write-back buffer | [`ch02_memory_hierarchy/writeback_nbcache`](../ch02_memory_hierarchy/writeback_nbcache) | 1-7 | done |
| Non-blocking cache (MSHRs, hit/miss under miss), coalescing write buffer | [`ch02_memory_hierarchy/nonblocking_cache`](../ch02_memory_hierarchy/nonblocking_cache) | 1-7 (write buffer), 2-7 (non-blocking) | done |
| Warehouse-scale computing | [`ch06_wsc`](../ch06_wsc) | 5-7 | partial Python analytical and queueing models; RTL fabric planned |

## 4. Which editions to read

For CPU microarchitecture, SystemVerilog and FPGA work the 3rd edition (deep scheduling, speculation,
VLIW/EPIC) paired with the 7th (modern whole-system view, RISC-V, accelerators) is a strong combination.
The 5th is an excellent snapshot of the shift to multicore, GPUs and cloud. The 1st and 2nd show how the
subject was taught when RISC pipelining and early superscalar designs were the frontier.

The fundamentals -- Amdahl's Law, locality, parallelism, pipeline hazards and quantitative measurement --
have survived more than 35 years; what changed is which techniques offered the best return.
