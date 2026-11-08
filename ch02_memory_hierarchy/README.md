# Chapter 2 -- Memory Hierarchy Design (with Appendix B)

Programs exhibit locality, so a hierarchy of small-fast to large-slow memories can look like one large fast
memory. The central metric is `AMAT = hit time + miss rate x miss penalty`, and the three classic miss
categories are **compulsory**, **capacity** and **conflict**. (In the 5th edition this material moved forward to
Chapter 2, with the review in Appendix B.)

## Examples

| Example | What it shows |
|---------|---------------|
| [`set_assoc_cache`](set_assoc_cache) | tag/index/offset, associativity, LRU, write-back + write-allocate, statistics |
| [`tlb_walker`](tlb_walker) | fully-associative TLB, hardware page-table walker, page and protection faults |
| [`victim_cache`](victim_cache) | direct-mapped cache + victim buffer: conflict misses removed by swapping evicted lines back |
| [`stride_prefetcher`](stride_prefetcher) | reference-prediction-table stride prefetcher: coverage, accuracy, pollution, timeliness |
| [`dram_controller`](dram_controller) | banked DRAM + timing checker; FR-FCFS vs FCFS, open vs closed page, refresh; miss 12 / hit 9 / conflict 15 cycles |
| [`nonblocking_cache`](nonblocking_cache) | MSHRs, hit-under-miss / miss-under-miss, secondary misses, coalescing write buffer; blocking 2157 vs miss-under-miss 674 cycles |

Planned: write-back non-blocking cache, a separate stream buffer
(see [`docs/roadmap.md`](../docs/roadmap.md)).
