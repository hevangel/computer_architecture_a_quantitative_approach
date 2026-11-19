# Two-Way Non-Blocking Write-Back Cache

**Topic:** Chapter 2, non-blocking write-back caches · **Edition:** 6th edition, §2.3 · **Files:** [SystemVerilog RTL](../writeback_nbcache/sv/wb_cache.sv), [VHDL RTL](../writeback_nbcache/vhdl/wb_cache.vhd), [SV test](sv/tb_nb_set_assoc_cache.sv), [VHDL test](vhdl/tb_nb_set_assoc_cache.vhd).

## Background

Multiple miss status holding registers allow hits and other misses to proceed while a line is being fetched. An associative cache reduces conflicts between lines mapping to one set, and a write-back buffer allows a dirty eviction to wait for memory. A later request to the buffered line must obtain the latest data rather than fetch a stale copy from memory. These implementations are original teaching models informed by the cited section.

## Design

This example configures the shared `wb_cache` as eight sets, two ways, four words per line, four MSHRs and a two-line FIFO write-back buffer. The least-recently-used way is updated on hits and installation; an invalid way is preferred. Loads and stores to an outstanding line merge in order, and the cache can accept hits and other misses while fills are pending. On a miss matching a buffered victim, the newest matching buffered line is copied to the MSHR without a memory read. The FIFO entry still drains to memory in order. `flush` must be asserted only when outstanding requests have finished. The memory model has a single port, ten-cycle reads and four-cycle writes. This is not a coherent multiprocessor cache.

## Verification

Both testbenches exercise the same directed trace: they make two conflicting lines dirty, touch one to choose the other as LRU, and re-read the victim while memory is disabled. They check its stored value, verify that no write has reached memory, then flush and check both values. A second trace checks a hit under two misses, a secondary miss, response data and counter deltas. A 200-operation seeded trace compares reads against a separate shadow memory and checks every word after flushing. An independent object-and-queue Python model also generates a 593-cycle trace of 192 requests. Both HDL benches compare request readiness, response IDs and data, memory-port commands and counters on every cycle. The trace fills all four MSHRs, stalls an additional miss, merges targets and forwards a buffered victim; the Python model checks responses against a sequential shadow memory.

## Run it

```sh
python -m unittest discover -s ch02_memory_hierarchy/nb_set_assoc_cache/python -v
python ch02_memory_hierarchy/nb_set_assoc_cache/python/generate_trace.py --check
python scripts/run_tests.py -v nb_set_assoc_cache
```

## Exercises

1. Compare latency and eviction traffic against the direct-mapped configuration on equal-capacity traces.
2. Extend the reference and tests to different associativities and non-FIFO memory replies.
3. Replace the serialized single memory port with a backpressured multi-bank interface.
