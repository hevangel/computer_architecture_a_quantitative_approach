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
| 7th | 2025 | Same seven chapter topics, updated CPU/GPU/accelerator coverage, more on SoCs and heterogeneous systems | RISC-V |

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
| 5-stage pipeline, hazards, forwarding (RV32I) | [`appC_pipelining/rv32i_pipeline5`](../appC_pipelining/rv32i_pipeline5) | 6-7 ISA; the pipeline itself 1-7 | done |
| 5-stage pipeline, branches in ID (DLX = `XLEN 32`, MIPS64 = `XLEN 64`) | [`appC_pipelining/mips_pipeline5`](../appC_pipelining/mips_pipeline5) | 1-2 (DLX), 3-5 (MIPS64) | done |
| 1-bit, 2-bit, correlating (gshare) prediction | [`ch03_ilp/branch_predictor`](../ch03_ilp/branch_predictor) | 1-7 | done |
| Cache: associativity, write-back, LRU | [`ch02_memory_hierarchy/set_assoc_cache`](../ch02_memory_hierarchy/set_assoc_cache) | 1-7 | done |
| Vector processor / lanes, DAXPY | [`ch04_dlp/vector_lanes`](../ch04_dlp/vector_lanes) | 1-7 (main chapter from 5th) | done |
| Vector chaining, convoys and chimes | [`ch04_dlp/vector_chaining`](../ch04_dlp/vector_chaining) | 1-7 (appendix G / Ch 4) | done |
| Snooping coherence (MESI) | [`ch05_tlp/mesi_snoopy`](../ch05_tlp/mesi_snoopy) | 2-7 | done |
| Systolic matrix unit (TPU) | [`ch07_dsa/systolic_array`](../ch07_dsa/systolic_array) | 6-7 | done |
| Computer arithmetic: CLA, Booth, division | [`appJ_arithmetic`](../appJ_arithmetic) | 1-7 (appendix) | done |
| ECC (SECDED) and RAID-5 parity | [`appD_storage`](../appD_storage) | 1-7 (main chapter through 4th, then supplemental) | done |
| Crossbar and arbitration | [`appF_interconnect/rr_crossbar`](../appF_interconnect/rr_crossbar) | 2-7 | done |
| Virtual channels: VC allocation, switch allocation, no head-of-line blocking | [`appF_interconnect/vc_router`](../appF_interconnect/vc_router) | 2-7 (interconnect material) | done |
| Mesh network: wormhole routing, credit flow control | [`appF_interconnect/mesh_router`](../appF_interconnect/mesh_router) | 2-7 (interconnect material) | done |
| Tomasulo + reorder buffer | [`ch03_ilp/tomasulo_rob`](../ch03_ilp/tomasulo_rob) | dynamic scheduling 2-7; ROB form from the 3rd | done |
| CDC 6600 scoreboard | [`ch03_ilp/scoreboard`](../ch03_ilp/scoreboard) | 2-7 (the early editions' dynamic-scheduling intro) | done |
| Hardware speculation (Tomasulo + ROB past branches) | [`ch03_ilp/tomasulo_spec`](../ch03_ilp/tomasulo_spec) | ROB form from the 3rd | done |
| VLIW (static multiple issue, exposed latencies) | [`appH_vliw/vliw4`](../appH_vliw/vliw4) | 3-4 main, later appendix | done |
| SIMD multimedia extensions (packed subwords, saturation, PMADD, PSAD) | [`ch04_dlp/simd_alu`](../ch04_dlp/simd_alu) | 5-7 (main chapter) | done |
| GPU SIMT core: warps, latency hiding, divergence | [`ch04_dlp/simt_core`](../ch04_dlp/simt_core) | 5-7 | done |
| TLB, page-table walker, protection | [`ch02_memory_hierarchy/tlb_walker`](../ch02_memory_hierarchy/tlb_walker) | 1-7 | done |
| Victim cache | [`ch02_memory_hierarchy/victim_cache`](../ch02_memory_hierarchy/victim_cache) | cache-optimization material (placement varies) | done |
| Hardware stride prefetching | [`ch02_memory_hierarchy/stride_prefetcher`](../ch02_memory_hierarchy/stride_prefetcher) | cache-optimization material (placement varies) | done |
| Banked DRAM controller: row buffers, FR-FCFS, refresh | [`ch02_memory_hierarchy/dram_controller`](../ch02_memory_hierarchy/dram_controller) | 2-7 | done |
| Write-back / write-allocate non-blocking cache, dirty bits, write-back buffer | [`ch02_memory_hierarchy/writeback_nbcache`](../ch02_memory_hierarchy/writeback_nbcache) | 1-7 | done |
| Non-blocking cache (MSHRs, hit/miss under miss), coalescing write buffer | [`ch02_memory_hierarchy/nonblocking_cache`](../ch02_memory_hierarchy/nonblocking_cache) | 1-7 (write buffer), 2-7 (non-blocking) | done |
| Warehouse-scale computing | `ch06_wsc` | 5-7 | no RTL planned (see its README) |

## 4. Which editions to read

For CPU microarchitecture, SystemVerilog and FPGA work the 3rd edition (deep scheduling, speculation,
VLIW/EPIC) paired with the 7th (modern whole-system view, RISC-V, accelerators) is a strong combination.
The 5th is an excellent snapshot of the shift to multicore, GPUs and cloud. The 1st and 2nd show how the
subject was taught when RISC pipelining and early superscalar designs were the frontier.

The fundamentals -- Amdahl's Law, locality, parallelism, pipeline hazards and quantitative measurement --
have survived more than 35 years; what changed is which techniques offered the best return.
