# Atomic Read-Modify-Write and Spin Locks on a Snooping Bus

**Topic:** Chapter 5 (synchronization: atomic exchange, fetch-and-add, spin locks and their cost on a cache-coherent bus) · **Editions:** 2-7 ·
**Files:** [`sv/spinlock_bench.sv`](sv/spinlock_bench.sv), [`vhdl/spinlock_bench.vhd`](vhdl/spinlock_bench.vhd)

## Background

Coherence ([`mesi_snoopy`](../mesi_snoopy), [`directory_msi`](../directory_msi)) keeps copies consistent but does not by itself let threads cooperate. Programs need **synchronization**, built on an
**atomic read-modify-write**: an instruction that reads a location and writes it with nothing intervening - *atomic exchange* (test-and-set), *fetch-and-add*, compare-and-swap, or load-linked / store-conditional.
On a coherent machine the atomic is implemented by obtaining the line in the **Modified** state and performing the read and the write while no other core can touch it.

A **spin lock** busy-waits on such an atomic. How it waits decides how much it loads the bus:

* **Test-and-set (TAS):** spin on `xchg(L, 1)` until it returns 0. Every attempt is a write, so every attempt needs the line in M: two or more spinners steal the line from each other and generate a
  **bus transaction per attempt**.
* **Test-and-test-and-set (TTAS):** spin with plain *loads* (the line stays in S in every spinner's cache: **no bus traffic while the lock is held**) and issue the exchange only when the lock reads free.
  Traffic occurs only when the lock is released (the release invalidates all copies, everyone re-reads, and the winner and the losers each try the exchange).
* **Ticket lock:** `fetch-and-add` on a ticket counter hands out numbers; each core spins with loads on `now_serving` until its number comes up; the release increments `now_serving`.
  Order is **FIFO** (no starvation), but a release still invalidates every waiter.

## Design

`spinlock_bench` has `P` cores on one write-invalidate (MSI) bus. Each core runs `N` iterations of: acquire; **critical section** = load a shared counter, `CS_LEN` cycles of work, store counter + 1; release; think
`NT` cycles. `LOCK` selects TAS (0), TTAS (1), ticket (2) or **no lock** (3, a control). Three lines are tracked: lock / next ticket, now-serving, and the counter.

* A memory operation that **hits** (load in S or M; store or atomic in M) takes 1 cycle and no bus traffic.
* A miss (load in I: **BusRd**; store or atomic in I or S: **BusRdX** / upgrade) arbitrates for the bus (round robin). A transaction takes `BUS_LAT` cycles: the coherence actions happen at the **grant**
  (BusRd: an owner in M drops to S; BusRdX: every other copy becomes I) and the operation **performs when the transaction completes**; an uncontended miss therefore costs `BUS_LAT` cycles.
* The coherence *states* of every line in every cache decide the traffic; the *values* live in one coherent memory image. This is enough to expose every effect described above.

Outputs: transaction counts (`stat_rd`, `stat_rdx`), cycles until all cores are done, the counter, the number of cores inside the critical section, and per-core pulses when a lock is acquired / a ticket is drawn.

## Verification

**One core, no contention** - everything after the first iteration hits, so the totals follow from the operation costs (`B` = `BUS_LAT` 4, `CS_LEN` 2, `NT` 3, `N` 5):

| Lock | First iteration | Later iterations | Cycles (`N = 5`) | BusRd / BusRdX |
|------|-----------------|------------------|-----------------:|----------------|
| TAS | exchange miss + counter load miss + counter upgrade = 3B + CS + 1 | 4 + CS | 3B + CS + 1 + 4(4 + CS + NT) = **51** | 1 / 2 |
| TTAS | load miss + exchange upgrade + counter load miss + counter upgrade = 4B + CS + 1 | 5 + CS | **59** | 2 / 2 |
| ticket | fetch-add miss + serving load miss + counter load miss + counter upgrade + release upgrade = 5B + CS | 5 + CS | **62** | 2 / 3 |

(and a TAS run with `BUS_LAT` 6, no work and no think time: 3 x 6 + 1 + 2 x 4 = **27**).

**Two cores, derived cycle by cycle** (`N = 1`, `CS_LEN` 0, `NT` 0; core 0 wins the first arbitration):

* **TAS - 33 cycles, 2 BusRd + 6 BusRdX.** c0 takes the lock line (0-3), c1's exchange (4-7) fails, c1 keeps the line in M and **retries with 1-cycle cache hits**; c0 reads the counter (8-11), upgrades it (12-15),
  its release steals the line from c1 (16-19); c1 takes it (20-23), reads and upgrades the counter (24-31), releases with a hit (32).
* **TTAS - 45 cycles, 5 BusRd + 6 BusRdX.** both read the lock (0-7) and see it free; c0 wins the exchange (8-11), c1's exchange fails (12-15) and c1 then **spins on hits in its cache**; c0 does its counter work (16-23)
  and releases (24-27, c1 invalidated); c1 re-reads (28-31), wins the exchange (32-35), counter (36-43), release hit (44).

**Many cores** (any correct lock): the counter equals `P * N` (no lost update), never more than one core inside the critical section, every core finishes its `N` iterations, and for the ticket lock the cores acquire in
**exactly the order they drew their tickets** (FIFO). The control without a lock proves the checks bite: with 4 cores and 24 increments the counter ends at **6** and up to **4 cores** are inside at once.

**Traffic** (4 cores x 6 critical sections = 24 acquisitions): bus transactions / cycles - **TAS 291 / 1169**, **TTAS 124 / 551**, ticket 166 / 712. Transactions per acquisition at 2 / 4 / 8 cores:

| | 2 cores | 4 cores | 8 cores |
|--|--:|--:|--:|
| TAS | 4.83 | 12.12 | **23.18** |
| TTAS | 2.58 | 5.16 | **9.70** |
| ticket | | | 10.58 |

Test-and-set's traffic per acquisition grows roughly in proportion to the number of waiters; TTAS and the ticket lock grow too (every release invalidates all waiting copies) but at roughly half the rate (TTAS needs 42-53 % of TAS's transactions).

Mutation checks that fail the testbench in both languages: an exchange that always succeeds, no invalidation on BusRdX (two cores then hold the line in M and the atomic is no longer atomic), a fixed-priority instead of
round-robin arbiter, TTAS spinning with the atomic instead of loads; (SystemVerilog also: a ticket release that skips a number). Both languages report identical numbers.

## Run it

```bash
make test T=spinlock_atomic
```

## Exercises

1. Add **exponential back-off** to TAS (wait 2^k cycles after the k-th failed attempt) and plot transactions against cores.
2. Implement **load-linked / store-conditional** (a link flag cleared by any invalidation of the line) and build the same lock and a lock-free counter increment with it; compare with `xchg`.
3. Give the lock holder a **long** critical section and show how TTAS's traffic is concentrated at the release (the *thundering herd*), then queue the waiters with an **array-based (Anderson) lock** where each waiter spins on its own line.
4. Add a **barrier** (`fetch-and-add` plus a sense-reversing flag) and measure its cost against the number of cores.
5. Replace the global value image by data carried in the caches and the snooping messages of [`mesi_snoopy`](../mesi_snoopy), and check that the atomicity argument still holds (what if two cores hit-write the same line?).
