# Chapter 5 -- Thread-Level Parallelism

Once single-thread performance stopped scaling, the answer was multicore. Programs then need **coherence**
(every core sees a consistent value for each address), **consistency** (a rule for the order in which other
cores observe writes) and **synchronization** (locks and atomics built on read-modify-write). Small machines
use **snooping** on a shared bus; larger ones use **directories**.

## Examples

| Example | What it shows |
|---------|---------------|
| [`mesi_snoopy`](mesi_snoopy) | MESI write-invalidate protocol, bus transactions, invariants |
| [`directory_msi`](directory_msi) | directory MSI protocol: sharer bit vectors, point-to-point messages, 2- and 4-hop transactions, message counts |

Planned: atomic RMW and spin locks, simple memory-consistency litmus tests (see
[`docs/roadmap.md`](../docs/roadmap.md)).
