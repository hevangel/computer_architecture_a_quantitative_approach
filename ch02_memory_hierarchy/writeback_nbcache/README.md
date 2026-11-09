# Non-Blocking Write-Back Cache: Dirty Lines, Write-Allocate and a Write-Back Buffer

**Topic:** Chapter 2 / Appendix B (write-back vs write-through, write-allocate, write buffers, non-blocking caches) · **Editions:** 1-7 ·
**Files:** [`sv/wb_cache.sv`](sv/wb_cache.sv), [`sv/wb_mem.sv`](sv/wb_mem.sv), [`vhdl/wb_cache.vhd`](vhdl/wb_cache.vhd), [`vhdl/wb_mem.vhd`](vhdl/wb_mem.vhd)

## Background

[`nonblocking_cache`](../nonblocking_cache) is **write-through**: every store goes to memory, so a buffer is needed to hide that traffic. Most real caches are
**write-back, write-allocate**: a store changes only the cache and sets a **dirty bit**; memory is updated only when a dirty line is **evicted**. Four stores to one line
become one line write instead of four word writes. Two costs appear:

* a *store miss* must fetch the line first (write-allocate), so stores need MSHRs too, and a load behind a store to the same word must see the store's value;
* an eviction may have to write a dirty **victim** back before (or while) the new line comes in. The standard fix is a **write-back (victim) buffer**: the victim is parked
  there and written to memory when the port is free, so the miss is not delayed by the write-back - but a later fetch of the parked line must wait for it.

## Design

Direct-mapped, 8 sets x 4 words, 8-bit word addresses, a valid and a dirty bit per line; generics as in the write-through version (`NM` MSHRs, `HUM` = 0 blocking,
`WBD` = write-back buffer depth in **lines**). Memory ([`wb_mem`](sv/wb_mem.sv)) moves whole lines: read latency 10, a line write occupies the port 4 cycles.

* **Hit:** loads answer next cycle; stores update the line and set the dirty bit - no memory traffic.
* **Miss (load or store):** allocate an MSHR, or join one whose fetch has not returned yet (up to 4 targets per MSHR, loads and stores mixed, kept in program order).
  A request to a line whose data has already returned but is not yet installed waits.
* **Line returns:** the MSHR's targets are processed one per cycle in order: a load answers (seeing every earlier store), a store patches the line and marks it dirty.
* **Install** (the cycle after the last target): the new line replaces the old one; a dirty victim is pushed into the write-back buffer. If the buffer is full the install waits.
  A request that hits the index being installed in that very cycle waits one cycle (otherwise a store could be lost between the victim copy and the new line).
* **Memory port:** a fetch beats a write-back, except that a fetch of a line still sitting in the write-back buffer must wait until that entry has been written.
* **Flush:** `flush = 1` on an idle cache pushes every dirty line through the buffer and raises `flush_done` when memory holds everything (used by the testbench to compare memory).

## Verification

Timeline of one miss on an idle cache, derived by hand: accepted c0; the MSHR is visible c1 and the fetch leaves; the line returns c11; c12 the first target is processed (a load
answers at **+12**); the last target is followed by the install, so an MSHR with one target is busy through c13 and the line is valid from c14.

| Test | Expectation | Result |
|------|-------------|--------|
| load hit / clean conflict miss | +1 / +12 | pass |
| hit under miss | non-blocking: accepted c1, answered c2; blocking: accepted c14, answered c15 | pass |
| miss under miss | `NM >= 2`: answers c12, c13; one MSHR or blocking: second accepted c14, answered c26 | pass |
| four loads of one line, a fifth behind them | answers c12-c15 (1 primary + 3 secondary misses); the fifth waits for the install at c16: accepted c17, answered c18 | pass |
| store miss, load of the same word right behind | load answered c13 with the store's value (blocking: accepted c14) | pass |
| dirty eviction | evicting load answered c12 (write-back off the critical path); the victim is written at c14 (port busy c15-c17), so re-reading it from c14 fetches at c18 and is answered c29 with the stored value; exactly one line write | pass |
| two dirty evictions, then re-read of the second victim while it is still in the buffer | the fetch must not leave at c18 (stale memory): the victim is written at c18, the fetch leaves c22, answered c33 | pass |
| four stores that hit, then eviction | accepted c0-c3, no line write; evicting the line costs exactly one line write | pass |

Then three 300-request random streams on every configuration: all loads return program-order values, no memory-protocol violation, and after a **flush** main memory equals the shadow memory.

| Stream (cycles for 300 requests) | blocking | hit-under-miss | miss-under-miss |
|----------------------------------|---------:|---------------:|----------------:|
| wide (20 % stores) | 3805 | 3720 | 930 |
| write-heavy (70 % stores) | 3829 | 3807 | 881 |

Write-back buffer of 1 / 2 / 4 lines on the write-heavy stream: 900 / 881 / 879 cycles. On the hot stream (90 % of accesses in 24 words) **125 stores became 34 line writes**.

Mutation checks (each fails the testbench in both languages): dropping the fetch-vs-write-back-buffer check, dropping the install/index block, installing when the buffer is full,
not setting the dirty bit on a store hit; in SystemVerilog also not setting it on a store merged into an MSHR, and never writing back.
Both languages produce identical numbers.

## Run it

```bash
make test T=writeback_nbcache
```

## Exercises

1. Forward from the write-back buffer: let a miss to a line that is parked there read it back instead of waiting for the memory write.
2. Add **critical-word-first** and early restart, and measure the load latency of a miss.
3. Make the cache 2-way set associative with LRU and compare dirty-eviction traffic on the streams.
4. Add a per-word dirty mask and write back only the dirty words (a *sectored* write-back), and count memory bandwidth.
5. Replace the install stall with a victim fetched *before* it is needed (eviction at fetch time) and compare latencies when the write-back buffer is full.
