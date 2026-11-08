# Non-Blocking Cache with MSHRs and a Coalescing Write Buffer

**Topic:** Chapter 2 (Advanced cache optimizations: non-blocking caches, write buffer, multibanking of misses) / Appendix B (write buffers, reducing miss penalty) ·
**Editions:** 1-7 (write buffers from the 1st, non-blocking caches and miss-status registers from the 2nd) ·
**Files:** [`sv/nb_cache.sv`](sv/nb_cache.sv), [`sv/nb_mem.sv`](sv/nb_mem.sv), [`vhdl/nb_cache.vhd`](vhdl/nb_cache.vhd), [`vhdl/nb_mem.vhd`](vhdl/nb_mem.vhd)

## Background

A **blocking** cache stops the processor on every miss, so the miss penalty is paid in full each time. A **non-blocking** cache lets the processor keep going:

* **hit under miss** - hits are served while one miss is outstanding;
* **miss under miss** - further misses are issued while others are outstanding, so their latencies overlap (memory-level parallelism).

The bookkeeping lives in **miss status holding registers (MSHRs)**: one per outstanding *line* fetch, remembering the line address and the loads waiting for it. A second miss to a
line that is already being fetched is a **secondary miss**; it only adds itself to the MSHR's target list. A **write buffer** decouples the processor from the slow write path of a
write-through cache: stores are queued and drained to memory in the background, and stores to the same address are **merged** in the buffer. The price is a set of ordering rules:
a read miss must not overtake a buffered write to the same line, and a store must not change a line while a fetch of it is in flight.

## Design

Direct-mapped, 8 sets x 4 words, 8-bit word addresses (`tag(3) | index(3) | offset(2)`), **write-through, no-write-allocate**. Generics select the configuration:

| Generic | Meaning |
|---------|---------|
| `NM` | number of MSHRs (outstanding line fetches), each with 4 target slots |
| `HUM` | `0`: blocking cache; `1`: the CPU port stays open while misses are outstanding (`NM = 1` hit-under-miss, `NM > 1` miss-under-miss) |
| `WBD` | write-buffer depth (`0` = none: a store is accepted only in a cycle in which memory takes it) |

CPU port: one request per cycle, `req_ready` is combinational and depends on the request presented (a hit can be accepted when a miss cannot). Read hits answer on `hit_*` the next
cycle; misses answer on `fill_*` after the line is installed, one waiting read per cycle, so answers can come **out of order**. Rules:

* **Miss path:** allocate an MSHR (or join one that is not yet filled and has a free slot); the fetch leaves for memory when memory is ready and no write-buffer entry holds a write to
  that line; the returned line is installed and handed to the MSHR, which frees itself after answering its last waiting read.
* **Write path:** update the cache on a hit, queue the write (merging with a buffered entry of the same address unless that entry is being sent right now). A store to a line with an MSHR
  active **waits** for the miss to finish. Memory fetches win the memory port over buffered stores.
* **Memory model** ([`nb_mem`](sv/nb_mem.sv)): read latency 10 cycles; a write occupies the port for 4 cycles, a read for 1; it flags a request presented while busy.

## Verification

Cycle numbers are derived by hand from these rules (cycle 0 = first accepted request; a read hit answers at +1, a read miss on an idle cache at +12 = 1 (request) + 10 (memory) + 1 (install)).
The same directed tests run on six configurations:

| Test | Expectation | Result |
|------|-------------|--------|
| hit / miss / conflict miss | answers at +1 / +12 / +12 | pass |
| hit under miss (R0 miss @0, R1 hit @1) | non-blocking: R1 accepted @1, answered @2; blocking: accepted @13, answered @14 | pass |
| miss under miss (two different lines @0, @1) | `NM >= 2`: answers @12, @13; one MSHR or blocking: second answered @25 | pass |
| four reads to one line @0..3, a fifth @4 | one fetch (1 primary + 3 secondary misses), answers @12,13,14,15; fifth hits when the line lands (accepted @12) | pass |
| W(A), W(L), R(L) with L missing | the read waits for the buffered write: answered @20, returns the buffered value | pass |
| write to a line with a miss outstanding | accepted @13 and visible to the next read | pass |
| 8 stores presented every cycle | accepted at 0 4 8 .. 28 (no buffer), 0 2 6 .. 26 (1 entry), 0 1 2 6 .. 22 (2), 0 1 2 3 4 6 10 14 (4) | pass |
| back-to-back stores to one address | the second is not lost when the first is being sent | pass |

Three 300-request random streams (hot region, wide, write heavy) then run on every configuration: each read must return the value of the program-order shadow memory, there must be no
memory-protocol violation, and after draining main memory must equal the shadow memory. Cycles for 300 requests:

| Stream | blocking | hit-under-miss | miss-under-miss (4 MSHRs) |
|--------|---------:|---------------:|--------------------------:|
| hot region (70 % of accesses in 64 words, 35 % stores) | 2157 | 1881 | 674 |
| wide (10 % hot, 20 % stores) | 2952 | 2658 | 719 |

| Write-heavy stream (75 % stores) | no buffer | 1 entry | 2 entries | 4 entries |
|----------------------------------|----------:|--------:|----------:|----------:|
| cycles for 300 requests | 948 | 937 | 925 | 895 |

The stores are bounded by memory (one store per 4 cycles), so the buffer only smooths bursts: the totals fall with depth but cannot beat the memory port.

Bugs the random streams found during development (both are now covered): a store that hits the *old* line in the cycle in which a new line is installed at the same index polluted the new line;
the VHDL write-buffer count was off by one when a push and a drain coincide. Mutation checks (each fails the testbench): dropping the read-vs-buffered-write check, dropping the
store-vs-MSHR block, merging into the entry being sent, letting stores beat fetches (SystemVerilog), and the install/store race (both languages). Both languages produce identical cycle totals.

## Run it

```bash
make test T=nonblocking_cache
```

## Exercises

1. Add **store-to-load forwarding** from the write buffer so a read miss to a line with buffered stores need not wait.
2. Let a store to a line with an MSHR outstanding proceed by recording it in the MSHR (a per-word patch applied when the line is installed).
3. Make the cache **write-back, write-allocate**: dirty bits, a victim buffer, and the extra hazard between a dirty eviction and a fetch of the same line.
4. Give the fill port a second lane and measure the effect on the 4-target MSHRs; then add **critical-word-first** so the demanded word is answered before the rest of the line arrives.
5. Sweep `NM` = 1..4 and the memory latency, and find the point where more MSHRs stop helping (the memory port saturates).
