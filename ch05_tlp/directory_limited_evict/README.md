# Directory Replacement and Limited Sharers

**Topic:** Directory coherence and replacement · **Editions:** 6th ed., Chapter 5 §5.4 · **Files:** [SystemVerilog](sv/directory_limited_evict.sv), [VHDL](vhdl/directory_limited_evict.vhd)

## Background

A home directory can record every sharer, or save space by recording a limited number and broadcasting when that capacity overflows. A coarse vector groups nodes and may invalidate caches that do not actually hold the block. Cache replacement must also release a shared line or write a modified line back to memory. These are original, simplified models of the concepts in the cited section.

## Design

Eight nodes have one private line each; four single-word blocks share a home. Requests are globally serialized and complete in one clock, with no modeled network latency, acknowledgments, races, or transient states. `MODE=0` stores a full vector, `MODE=1` uses two pointers followed by broadcast on overflow, and `MODE=2` stores a bit per pair of nodes. A shared eviction generates PutS; a modified eviction generates PutM and writes the victim to memory. To remain conservative, coarse bits and an overflow indication are retained after clean evictions until a write or owner transition clears them. This can cause spurious invalidations. Counters count invalidation destinations, PutS, PutM and dirty-owner fetches, not total network messages. Debug ports inspect a node, block, and potential invalidation targets.

## Verification

The independently implemented Python reference enforces clean-memory, single-owner, and sharer-coverage invariants after every operation. It generates the identical directed and seeded traces in both HDL testbenches: 13 directed operations and 256 random requests. Each response, traffic counter, requested block state, memory and target vector, and requesting cache line is checked. For sharers 0 and 2 followed by a write from node 7, the full, limited, and coarse directories send 2, 2, and 4 invalidations. After a dirty replacement, four sharers followed by a write from node 7 increase their cumulative counts to 6, 9, and 11 respectively. Dirty replacement and subsequent reads test write-back data. A passing trace does not establish correctness under concurrent or asynchronous requests.

## Run it

```sh
python scripts/run_tests.py -v directory_limited_evict
```

Regenerate both testbenches with `python ch05_tlp/directory_limited_evict/python/generate_tests.py` after changing the reference or stimulus.

## Exercises

1. Add finite-latency requests, acknowledgment tracking and transient states.
2. Measure the additional storage and traffic for different directory sizes and group widths.
3. Replace conservative stale groups with exact group occupancy tracking.
