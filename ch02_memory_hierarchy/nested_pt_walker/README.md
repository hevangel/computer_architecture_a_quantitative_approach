# Nested Guest and Host Page-Table Walker

**Topic:** Nested address translation, page-walk caches and TLBs · **Edition:** 6th edition, Appendix L · **Files:** [SystemVerilog](sv/nested_pt_walker.sv), [VHDL](vhdl/nested_pt_walker.vhd), [Python reference](python/nested_reference.py)

## Background

A nested walk translates each guest page-table access through host page tables, then translates the final guest physical address. A page-walk cache can reuse previously read entries; an ASID-tagged TLB can avoid a walk altogether. These are original teaching models with a simplified PTE format, not an implementation of a particular ISA.

## Design

Both stages use an 11-bit root index and a 9-bit leaf index, with 4 KiB leaves or 2 MiB root-level superpages. A PTE has a valid bit at bit 0, a root-superpage bit at bit 1, and a base in bits 31:12. Root tables are 8 KiB aligned. A guest PTE address first undergoes a host walk. The final TLB page size is the smaller of the guest and host page sizes.

The hardware serializes requests and has one outstanding memory read. `mem_valid` and `mem_addr` remain stable until `mem_ready`; `mem_rvalid` returns the word no earlier than the following cycle. Its 16-entry FIFO page-walk cache is optional per request. Its four-entry LRU TLB includes the ASID, both root addresses, and page size in its match. `invalidate` clears both structures when idle; the caller must invalidate after changing mappings or reusing an address space. Counters record accepted memory reads, page-walk-cache hits and TLB hits. Invalid entries, a superpage bit in a leaf, misaligned superpages and misaligned roots fault. Permissions, concurrent walks, architectural exception codes and targeted shootdowns are outside this model.

## Verification

Both HDL testbenches run the same directed and seeded traces. Expected results and read counts are derived from the independent Python model and hand-checkable page tables:

| Scenario | Host-memory reads |
| --- | ---: |
| Two-level guest and host, no walk cache | 8 |
| Same translation, TLB hit | 0 |
| First translation with walk cache | 6 |
| Adjacent guest page with walk cache | 2 |
| Guest and host superpages, no walk cache | 4 |
| Guest superpage with host 4 KiB page | 5 |

The tests also hold memory backpressure for three cycles, check two ASIDs without a flush, mixed page sizes, four-entry LRU replacement, faults, and 128 seeded translations. SV and VHDL complete at the same simulated time. The separate Python tests cover the functional reference; its page-walk cache is unbounded and its default TLB has eight entries, unlike the finite hardware structures.

## Run it

```sh
python -m unittest discover -s ch02_memory_hierarchy/nested_pt_walker/python -v
python scripts/run_tests.py -v nested_pt_walker
```

## Exercises

1. Add permissions and distinguish guest-stage from host-stage faults.
2. Support multiple concurrent walks and tagged out-of-order memory replies.
3. Add address- and ASID-scoped shootdowns with explicit synchronization.
