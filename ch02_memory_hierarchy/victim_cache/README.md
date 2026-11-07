# Victim Cache

**Topic:** Chapter 2 / Appendix B (cache organization and the classic miss-reduction optimizations) · **Editions:** a standard cache optimization in the book's
cache-improvement discussions (placement varies by edition) · **Files:** [`sv/victim_cache.sv`](sv/victim_cache.sv), [`vhdl/victim_cache.vhd`](vhdl/victim_cache.vhd)

## Background

Cache misses fall into three categories -- **compulsory** (first touch), **capacity** (the working set does not fit) and **conflict** (too many hot blocks map to the
same set). A direct-mapped cache is the fastest to access but suffers conflict misses most: two hot lines that share a set evict each other on every access ("thrashing"),
even though the rest of the cache is nearly empty.

Jouppi's **victim cache** (1990) adds a tiny fully-associative buffer next to the cache that holds the lines most recently *evicted* from it:

```
L1 miss  ->  probe the victim buffer
   hit   ->  SWAP: the victim line moves into L1, the evicted L1 line takes its place in the buffer      (no memory access)
   miss  ->  fetch from memory into L1; the line L1 throws out goes into the buffer (replacing its LRU entry)
```

It keeps direct-mapped hit time but recovers much of the associativity benefit, because the lines that thrash are exactly the ones recently evicted.

## Design

* Direct-mapped L1 (`SETS = 4`, `LINE_WORDS = 4`) + `VICT` fully-associative victim entries with true LRU. `VICT = 0` is the plain direct-mapped cache.
* Read-only model (like an instruction cache), word addresses. A request is held until `resp_valid`.
* **Timing:** L1 hit answers in the same cycle (1 cycle). A victim hit does the swap in one edge and then the request *replays* as an L1 hit (2 cycles, no memory access). A miss in both goes to
  memory and costs `MEM_LAT + 3` cycles with the testbench memory (6 for the 3-cycle memory).
* Statistics: `stat_l1_hits`, `stat_victim_hits`, `stat_misses` (memory fetches).

## Verification

Lines 0, 4 and 8 all map to set 0. Expected counters (l1 hits / victim hits / misses) come from an **independent Python model** of LRU victim replacement, and each testbench checks
every returned word, the counters, and that total cycles equal `1 x l1_hits + 2 x victim_hits + 6 x misses`:

| Trace | no victim cache | 1 entry | 2 entries | 4 entries |
|-------|----------------:|--------:|----------:|----------:|
| `0 4 0 4 ...` (12 accesses, 2 lines fight) | 12 misses | **2** | 2 | 2 |
| `0 4 8 0 4 8 ...` (12 accesses, 3 lines fight) | 12 | 12 | **3** | 3 |
| random over 12 lines (400 accesses) | 266 | 234 | 191 | **125** |

Two points the table makes: the buffer must be at least as big as the number of conflicting lines minus one (a 1-entry buffer does nothing for three thrashing lines), and on a realistic mix the benefit
grows with size with diminishing returns. On the 400-access trace the total cycles fall from 1 730 to 1 602, 1 430 and 1 166 (average 4.33 -> 2.92 cycles per access, -33 %). Disabling the
"save the evicted line" step makes the test fail.

## Run it

```bash
make test T=victim_cache
```

## Exercises

1. Make it a **write-back** cache: dirty bits must travel with the lines through the swap.
2. Replace LRU in the buffer with FIFO and compare on the random trace.
3. Compare a 4-entry victim cache with simply making L1 **2-way set-associative** at equal storage -- which wins, and what does each cost in hit time?
4. Add the **miss cache** variant (the buffer is filled on *every* miss, not only on evictions) and show why the victim cache is better.
