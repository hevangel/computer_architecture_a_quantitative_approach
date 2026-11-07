# Stride Prefetcher

**Topic:** Chapter 2 (hardware prefetching, reducing miss penalty and miss rate through parallelism) · **Editions:** a standard cache optimization (placement varies by edition) ·
**Files:** [`sv/stride_prefetcher.sv`](sv/stride_prefetcher.sv), [`vhdl/stride_prefetcher.vhd`](vhdl/stride_prefetcher.vhd)

## Background

Many programs walk arrays in a regular pattern. A **prefetcher** predicts the next address and fetches it before the processor asks, overlapping memory latency with useful work. It is judged on:

* **coverage** -- how many demand misses it eliminates;
* **accuracy** -- the fraction of prefetches that are later used (`useful / issued`); useless ones waste bandwidth and can evict live data (**cache pollution**);
* **timeliness** -- a prefetch must complete *before* the demand access, or it only shortens the wait.

A **stride prefetcher** (reference prediction table, Chen & Baer) learns per static instruction: the table is indexed by the load's PC and holds the last address, the last stride and a confidence counter.

```
new stride == remembered stride (and != 0)  ->  confidence + 1 (saturating at 2)
otherwise                                   ->  stride := new stride,  confidence := 0
confidence >= THRESH (here 1: two equal strides in a row)  ->  prefetch  address + stride
```

## Design

* Direct-mapped cache (`SETS = 8`, `LINE_WORDS = 4`), a 4-entry reference prediction table indexed by `req_pc`, and one pending prefetch slot. `PREFETCH = 0` gives the plain cache.
* **Demand has priority.** A prefetch starts only when the cache is idle; a demand request that arrives during a prefetch waits for it. A prefetch whose target line is already resident is dropped (not counted).
* Prefetched lines are installed with a **prefetched bit**; the first demand hit on such a line increments `stat_pf_useful` and clears the bit.
* Statistics: `stat_hits` (includes hits on prefetched lines), `stat_misses`, `stat_pf_issued`, `stat_pf_useful`.

## Verification

The testbench runs four workloads cold, with and without the prefetcher, in two regimes. In the **long-gap** regime (12 compute cycles between accesses, so each prefetch finishes before the next demand access) the
counters are predicted *exactly* by an independent Python functional model, and demand-wait cycles equal `1 x hits + 6 x misses`:

| Workload (accesses) | misses without | misses with | prefetches (useful) | accuracy | demand-wait cycles without -> with |
|---|---:|---:|---:|---:|---|
| unit stride, 4 accesses per line (64) | 16 | **1** | 16 (15) | 94 % | 144 -> **69** |
| stride = one line (48) | 48 | **3** | 46 (45) | 98 % | 288 -> **63** |
| random addresses (120) | 105 | 105 | **0** (0) | -- | 645 -> 645 |
| stream + hot variable in a shared set (120) | 44 | **16** | 37 (32) | 86 % | 340 -> **200** |

* The **random** workload shows the safe failure mode: no stride ever repeats, so the table never reaches confidence and *nothing* is prefetched -- no bandwidth wasted, no pollution.
* The last row is the **cost side**: 5 of 37 prefetches were wasted and some evicted the hot line early, yet the net effect is still positive.
* The final prefetch of each stream runs one element past the end of the array (16 issued, 15 useful) -- the unavoidable cost of predicting beyond the last access.

**Timeliness matters.** With **zero** compute between accesses the prefetcher cannot get idle cycles and demand accesses can queue behind it. The same hit/miss improvements are partly lost, and on the mixed
workload prefetching is slightly **worse** (348 vs 340 demand-wait cycles) despite 28 fewer misses:

| Demand-wait cycles | unit | stride = line | random | mix |
|---|---:|---:|---:|---:|
| without prefetch | 144 | 288 | 645 | 340 |
| with prefetch, 12-cycle gap | 69 | 63 | 645 | 200 |
| with prefetch, no gap | 129 | 243 | 645 | **348** |

In the zero-gap regime the testbench checks only that every returned word is correct and that `hits + misses` equals the number of accesses (the idealised model does not apply there); the numbers above are what it measures.
Mutating the "useful bit" bookkeeping makes the exact tests fail.

## Run it

```bash
make test T=stride_prefetcher
```

## Exercises

1. Raise `THRESH` to 2 and measure the accuracy/coverage trade-off (later start, fewer wasted prefetches).
2. Prefetch **degree 2** (two lines ahead) and **distance** (further ahead) to hide a longer memory latency in the zero-gap regime.
3. Put the prefetched lines in a small separate **stream buffer** instead of the cache and show that pollution disappears.
4. Add a next-line prefetcher (no PC, no table) and compare on the four workloads.
5. Give demand and prefetch a real **priority arbiter** with a second memory port and re-measure the zero-gap regime.
