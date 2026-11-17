# Chapter 2 -- Memory Hierarchy Design (with Appendix B)

Programs exhibit locality, so a hierarchy of small-fast to large-slow memories can look like one large fast
memory. The central metric is `AMAT = hit time + miss rate x miss penalty`, and the three classic miss
categories are **compulsory**, **capacity** and **conflict**. (In the 5th edition this material moved forward to
Chapter 2, with the review in Appendix B.)

## Examples

| Example | What it shows |
|---------|---------------|
| [`cache_3c_policies`](cache_3c_policies) | finite-address compulsory/capacity/conflict classification and four replacement policies |
| [`set_assoc_cache`](set_assoc_cache) | tag/index/offset, associativity, LRU, write-back + write-allocate, statistics |
| [`tlb_walker`](tlb_walker) | fully-associative TLB, hardware page-table walker, page and protection faults |
| [`victim_cache`](victim_cache) | direct-mapped cache + victim buffer: conflict misses removed by swapping evicted lines back |
| [`stride_prefetcher`](stride_prefetcher) | reference-prediction-table stride prefetcher: coverage, accuracy, pollution, timeliness |
| [`stream_buffer`](stream_buffer) | four-entry sequential stream buffer below a direct-mapped L1; demand versus prefetch traffic |
| [`prime_probe_qos`](prime_probe_qos) | shared-cache replacement channel and way partitioning |
| [`alloy_dram_cache`](alloy_dram_cache) | direct-mapped tag/data cache with illustrative miss prediction |
| [`dram_controller`](dram_controller) | banked DRAM + timing checker; FR-FCFS vs FCFS, open vs closed page, refresh; miss 12 / hit 9 / conflict 15 cycles |
| [`nonblocking_cache`](nonblocking_cache) | MSHRs, hit-under-miss / miss-under-miss, secondary misses, coalescing write buffer; blocking 2157 vs miss-under-miss 674 cycles |
| [`nested_pt_walker`](nested_pt_walker) | nested guest/host page walks, page-walk cache and ASID TLB |
| [`way_predict_vipt`](way_predict_vipt) | way prediction, safe VIPT indexing and critical-word-first refill |
| [`nb_set_assoc_cache`](nb_set_assoc_cache) | two-way non-blocking write-back, LRU and victim forwarding |
| [`writeback_nbcache`](writeback_nbcache) | the write-back version: dirty bits, write-allocate store misses, write-back (victim) buffer, flush; 125 stores -> 34 line writes |

Further work is listed in [`docs/roadmap.md`](../docs/roadmap.md).
