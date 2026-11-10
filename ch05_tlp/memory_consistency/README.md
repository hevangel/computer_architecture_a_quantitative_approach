# Memory Consistency Models: Exhaustive Litmus Tests

**Topic:** Chapter 5 (models of memory consistency: sequential consistency, relaxed models, fences) · **Editions:** 2-7 ·
**Files:** [`sv/consistency_model.sv`](sv/consistency_model.sv), [`vhdl/consistency_model.vhd`](vhdl/consistency_model.vhd)

## Background

Cache **coherence** ([`mesi_snoopy`](../mesi_snoopy), [`directory_msi`](../directory_msi)) says every core sees one order of writes to *each address*. **Consistency** says in what order a core's reads and writes to
*different* addresses may appear to other cores. The simplest rule, **sequential consistency (SC)**, is that the result is as if all operations ran in some single interleaving that respects each core's program order. It is
easy to reason about and slow to implement, so real machines relax it - chiefly by giving each core a **store buffer** so that stores do not stall the pipeline:

* **TSO** (x86, SPARC TSO): a core's stores sit in a FIFO buffer and become visible to the others in order, but a core may read a *later* location before its *earlier* store is visible - and reads its own buffered stores
  (**store-to-load forwarding**). This relaxes *store -> load* order only.
* **PSO** (SPARC PSO): stores to *different* addresses may also leave the buffer out of order - *store -> store* order is relaxed too.
* **Fences** restore order on demand: a FENCE waits until the core's earlier stores are visible.

The way to explore a model is a **litmus test**: a few instructions on two to four cores, and the set of final register values the model allows. The set of *allowed* outcomes is the model.

## Design

`consistency_model` is a machine of `P` cores with tiny programs (`ST addr,val`, `LD reg,addr`, `FENCE`), four memory words and, for TSO and PSO, a per-core store buffer. Nothing runs on its own: a **scheduler** (the testbench)
picks one *enabled action* per cycle - "core *c* executes its next instruction" or "core *c* drains buffer entry *j* to memory" - so every interleaving can be forced. `enabled` shows which actions are possible; when none is, the run is over.

| `MODEL` | Stores | Loads | Drain |
|--------:|--------|-------|-------|
| 0 SC | write memory immediately | read memory | - |
| 1 TSO | enter a FIFO buffer | youngest buffered store to the address, else memory | oldest entry only |
| 2 PSO | as TSO | as TSO | any entry with no older entry to the same address |

All three are *multi-copy atomic*: once a store has left its buffer every core sees it. (POWER and ARMv7 are not, which is what separates the last two columns of the textbook's litmus-test tables.)

## Verification

For every program the testbench **enumerates all schedules** - depth-first over the enabled actions, re-running the machine from reset for each schedule - and collects the set of final outcomes. It must equal the set **derived by hand**:
no forbidden outcome may ever occur and every allowed one must. (`x`, `y` start at 0, every store writes 1.)

| Test | Programs | Outcome | SC | TSO | PSO |
|------|----------|---------|:--:|:---:|:---:|
| **SB** (store buffering) | `x=1; r0=y` ‖ `y=1; r0=x` | (r0, r0) = 0,0 | forbidden | **allowed** | **allowed** |
| SB + fences | a `FENCE` between store and load in both | 0,0 | forbidden | forbidden | forbidden |
| **MP** (message passing) | `x=1; y=1` ‖ `r0=y; r1=x` | (1,0) | forbidden | forbidden | **allowed** |
| MP + fence | a `FENCE` between the two stores | (1,0) | forbidden | forbidden | forbidden |
| **LB** (load buffering) | `r0=x; y=1` ‖ `r0=y; x=1` | (1,1) | forbidden | forbidden | forbidden (needs load reordering: allowed on ARM/POWER) |
| **IRIW** | `x=1` ‖ `y=1` ‖ `r0=x; r1=y` ‖ `r0=y; r1=x` | readers disagree: 1,0 and 1,0 | forbidden | forbidden | forbidden (multi-copy atomic) |
| **SB + forwarding** | `x=1; r0=x; r1=y` ‖ `y=1; r0=y; r1=x` | r0 = 1 and r1 = 0 in both cores | forbidden | **allowed** | **allowed** |
| **WRC** (causality) | `x=1` ‖ `r0=x; y=1` ‖ `r0=y; r1=x` | 1, 1, 0 | forbidden | forbidden | forbidden |

Reading the table: TSO is weaker than SC only through **SB** (a load overtakes the core's own buffered store) and **forwarding**; PSO adds **MP** (stores overtake each other); fences close the holes. In every case the number
of distinct outcomes found equals the hand-derived count (for example SB 3 / 4 / 4, MP 3 / 3 / 4, IRIW 15 in all three).

**Schedule counts.** Under SC a schedule is an interleaving of the programs, so the number explored is the multinomial coefficient of the program lengths, which the testbench asserts: SB `4!/(2!2!)` = 6,
SB + fences `6!/(3!3!)` = 20, MP 6, MP + fence `5!/(3!2!)` = 10, LB 6, **IRIW `6!/(1!1!2!2!)` = 180**, SB + forwarding 20, WRC `5!/(1!2!2!)` = 30. With store buffers the drain actions add interleavings: 278 schedules in all for SC,
3581 for TSO and 3596 for PSO (IRIW alone: 2520).

Mutation checks that fail the testbench in both languages: removing store-to-load forwarding (SB + forwarding then shows the wrong set), letting TSO drain any entry (MP then shows 1,0), a FENCE that does not wait for the buffer
(SB + fences then shows 0,0); (SystemVerilog also: SC stores going through a buffer). Both languages explore the same schedules and end at the same simulated time.

## Run it

```bash
make test T=memory_consistency
```

## Exercises

1. Add **load reordering** (a load may execute before an earlier load or store to a different address) and show that LB's (1,1) and MP's (1,0) become allowed - the ARM/POWER behaviour.
2. Make memory **non-multi-copy-atomic** (each core has its own view of a drained store, updated at different times) and find the IRIW outcome that was forbidden here.
3. Add an **acquire/release** annotation to loads and stores and rewrite MP so that it is correct without a full fence.
4. Add a **coherence** test (CoRR/CoWW: two reads of one address, two writes to one address) and show that every model here, even PSO, keeps per-address order.
5. Run the lock of [`spinlock_atomic`](../spinlock_atomic) on this machine and show what breaks in the TSO model if the release is a plain store without the fence the acquire side expects.
