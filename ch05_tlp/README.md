# Chapter 5 -- Thread-Level Parallelism

Once single-thread performance stopped scaling, the answer was multicore. Programs then need **coherence**
(every core sees a consistent value for each address), **consistency** (a rule for the order in which other
cores observe writes) and **synchronization** (locks and atomics built on read-modify-write). Small machines
use **snooping** on a shared bus; larger ones use **directories**.

## Examples

| Example | What it shows |
|---------|---------------|
| [`mesi_snoopy`](mesi_snoopy) | MESI write-invalidate protocol, bus transactions, invariants |
| [`llsc_backoff_barrier`](llsc_backoff_barrier) | LR/SC reservations, TTAS backoff and sense-reversing barrier |
| [`spinlock_atomic`](spinlock_atomic) | atomic exchange / fetch-and-add, TAS vs TTAS vs ticket locks on a snooping bus, bus traffic per acquisition |
| [`directory_limited_evict`](directory_limited_evict) | clean and dirty replacement, limited sharers and coarse directories |
| [`directory_msi`](directory_msi) | directory MSI protocol: sharer bit vectors, point-to-point messages, 2- and 4-hop transactions, message counts |
| [`consistency_litmus_tsosb`](consistency_litmus_tsosb) | SC and buffered TSO store-buffering and message-passing tests |

Further work is listed in
[`docs/roadmap.md`](../docs/roadmap.md).
