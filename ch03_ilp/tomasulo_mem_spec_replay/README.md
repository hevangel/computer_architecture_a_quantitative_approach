# Tomasulo Memory Speculation and Recovery

**Topic:** Memory dependence speculation, replay and branch recovery · **Edition:** 6th edition, Chapter 3 §§3.6 and 3.9 · **Files:** [SystemVerilog](sv/tomasulo_mem_spec_replay.sv), [VHDL](vhdl/tomasulo_mem_spec_replay.vhd)

## Background

A younger load can execute before an older store has computed its address, but it must be repaired if that store later resolves to the same address. A branch can also be redirected before it reaches the head of the reorder buffer. This original teaching model extends the repository's [`tomasulo_lsq`](../tomasulo_lsq), using its small educational ISA and idealized memory.

## Design

The default configuration has an eight-entry ROB and load/store queue, three add stations, two multiply stations, a single load unit and one common data bus. Stores update the 64-word memory only at commit. A load may bypass unresolved older store addresses; it records which stores were unknown when it started. When one resolves to the load's address, the oldest violating load and all younger instructions are squashed and refetched. Older ROB and LSQ entries, their functional units and committed state remain intact. Rename mappings are rebuilt from the surviving ROB. The rule can replay unnecessarily when a still-younger older store already supplies the correct value; it favors a simple conservative repair over a more selective dependency graph.

A branch misprediction recovers when the branch result is broadcast on the common data bus. The branch and older entries survive while younger entries are discarded. If a branch recovery and a memory violation coincide, the older recovery boundary wins. New functional units do not start work on a recovery edge. `SPEC_MEM` and `RESOLVE_BRANCH` can separately disable these behaviors for comparison. The ring implementation assumes power-of-two ROB and LSQ capacities. This model does not implement byte-level memory aliasing, an external cache, exceptions or multiple simultaneous load units.

`stat_replays`, `stat_flushes`, `stat_squashed` and `stat_fwd` count speculative events; they may include operations subsequently squashed by an older recovery. In particular, resolve-time branch flushes need not equal the number of taken branches that eventually commit.

## Verification

The same testbench runs three configurations: conservative memory and commit-time branch recovery; speculative memory and resolve-time recovery; and the latter with backward-taken prediction. With multiply latency set to eight cycles, an independent load behind a late-address store reduces execution from **19 to 16 cycles**. An alias causes replay, and the load and dependent instruction receive the stored value. A branch resolving behind an older multiply finishes in **15 rather than 22 cycles** while preserving that multiply and preventing a wrong-path store.

Additional directed programs check two late aliasing stores and youngest-store forwarding, a younger write-after-write chain, ROB wraparound, and both taken and not-taken backward-branch recovery. A sequential interpreter checks every register, all 64 memory words and committed operation counts for 100 deterministic mixed programs; the speculative configuration performs five replays on that stream. Both HDL simulations finish at the same simulated time.

## Run it

```sh
python scripts/run_tests.py -v tomasulo_mem_spec_replay
```

## Exercises

1. Avoid unnecessary replay when a younger older store already supplies the load's value.
2. Add variable-latency memory and multiple outstanding load responses with unique tags.
3. Replace suffix refetch with dependency-directed selective replay and precise exceptions.
