# Chapter 5 -- Thread-Level Parallelism

Once single-thread performance stopped scaling, the answer was multicore. Programs then need **coherence**
(every core sees a consistent value for each address), **consistency** (a rule for the order in which other
cores observe writes) and **synchronization** (locks and atomics built on read-modify-write). Small machines
use **snooping** on a shared bus; larger ones use **directories**.

## Examples

| Example | What it shows |
|---------|---------------|
| [`mesi_snoopy`](mesi_snoopy) | MESI write-invalidate protocol, bus transactions, invariants |
| [`memory_consistency`](memory_consistency) | SC vs TSO vs PSO: store buffers, forwarding, fences; every litmus-test outcome set found by exhaustive schedule enumeration |
| [`spinlock_atomic`](spinlock_atomic) | atomic exchange / fetch-and-add, TAS vs TTAS vs ticket locks on a snooping bus, bus traffic per acquisition |
| [`directory_msi`](directory_msi) | directory MSI protocol: sharer bit vectors, point-to-point messages, 2- and 4-hop transactions, message counts |

Planned: weaker models (load reordering, non-multi-copy-atomic), LL/SC (see
[`docs/roadmap.md`](../docs/roadmap.md)).
