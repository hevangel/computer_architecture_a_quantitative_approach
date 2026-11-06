# A 4-Slot VLIW Core with an Exposed Pipeline

**Topic:** Appendix H (Hardware and Software for VLIW and EPIC) and the software-scheduling half of Chapter 3 · **Editions:** prominent in
the main text of the 3rd and 4th, later an appendix · **Files:** [`sv/vliw4.sv`](sv/vliw4.sv), [`vhdl/vliw4.vhd`](vhdl/vliw4.vhd)

## Background

Out-of-order machines such as [`tomasulo_rob`](../../ch03_ilp/tomasulo_rob) find instruction-level parallelism *in hardware*, at run time, and
pay for it in area and power. A **VLIW** (very long instruction word) machine moves that job to the **compiler**: it packs independent operations
into one wide instruction word -- a *bundle* -- and the hardware simply issues the whole bundle every cycle, with no dependence checking.

| | Dynamic (superscalar / Tomasulo) | Static (VLIW) |
|---|---|---|
| who finds the parallelism | hardware, every run | compiler, once |
| hazard detection | interlocks, renaming, ROB | **none**: the schedule must be correct |
| code | compact, ISA unchanged across generations | wide; unused slots are **NOPs** (code bloat); tied to the pipeline's latencies |
| hardware | complex, power-hungry | simple |

The compiler's tools are **loop unrolling** (more independent work per iteration) and **software pipelining**; the price of a rigid schedule is
code size and binary incompatibility across implementations -- the problems the Itanium/EPIC designs tried to soften.

## Design

A 128-bit bundle holds four 32-bit operations, one per slot:

| Slot | Unit | Operations | Result visible |
|------|------|------------|----------------|
| 0, 1 | integer ALU | `ADD` `SUB` `MUL` `ADDI` | in the **next** bundle |
| 2 | memory | `LD` `ST` | a load's value is visible **2 bundles later** |
| 3 | control | `BNEZ` `JMP` `HALT` | taken branch redirects immediately (no delay slot) |

* 16 registers, `r0 = 0`. Operation word: `[31:28] opcode | [27:24] rd | [23:20] ra | [19:16] rb | [15:0] imm`.
* **Exposed pipeline.** There are no interlocks and no forwarding: a register read before a load has landed returns its **old value**, so the
  programmer/compiler must leave the gap. This is the defining property of the model.
* **Parallel semantics.** All slots read the register file as it stood at the *start* of the bundle, so a bundle can swap two registers or read
  an old `r2` while another slot increments it.
* An operation in a slot that cannot execute it acts as a NOP. Two writes to one register in one cycle are undefined (the schedule must avoid it).
* `stat_bundles` equals cycles (one bundle per cycle, no stalls); `stat_ops` counts non-NOP operations, so **IPC = ops / bundles**.

## Verification

The kernel is `y[i] = a*x[i] + y[i]` for 8 elements (`a = 3`, `x[i] = i + 1`, `y[i] = 100 i`; expected `y[i] = 103 i + 3`), scheduled three ways. The load
latency of 2 bundles is what dictates the gaps:

**PROG 0 -- one operation per bundle** (9 bundles per iteration, like a scalar machine)

```
ld r3,[r1]  | ld r4,[r2]  | mul r5,r3,r7 | add r6,r5,r4 | st [r2],r6 | addi r1 | addi r2 | addi r8,-1 | bnez r8
```

**PROG 1 -- packed within an iteration** (5 bundles: independent address/counter updates ride along with the loads, the store and the branch)

```
b2: addi r8,r8,-1           | ld r3,[r1]
b3: addi r1,r1,4            | ld r4,[r2]
b4: mul  r5,r3,r7
b5: add  r6,r5,r4
b6: addi r2,r2,4            | st [r2],r6 (old r2) | bnez r8
```

**PROG 2 -- unrolled x2 and rescheduled** (7 bundles per *two* elements: the memory slot is the bottleneck, 6 memory ops)

```
b2: addi r8         | ld r3,[r1]        b6: add r6,r5,r4
b3:                 | ld r9,[r1+4]      b7: add r12,r11,r10 | st [r2],r6
b4: mul r5 | addi r1,8 | ld r4,[r2]     b8: addi r2,8       | st [r2+4],r12 | bnez r8
b5: mul r11         | ld r10,[r2+4]
```

| Version | Bundles (= cycles) | Operations | IPC | Speedup vs. PROG 0 |
|---------|-------:|------:|----:|------:|
| PROG 0 -- scalar-style | 75 | 76 | 1.01 | 1.00x |
| PROG 1 -- packed | 43 | 76 | 1.77 | 1.74x |
| PROG 2 -- unrolled x2 | 31 | 60 | 1.94 | 2.42x |

The counts are derived by hand from the schedules (2 setup bundles + iterations x bundles-per-iteration + the halt) and asserted exactly; all eight
`y[i]` results are checked in memory. A fourth program (**PROG 3**) tests the exposed pipeline directly: it sets `r3 = 77`, issues `ld r3` (memory holds
1), then reads `r3` one bundle too early (expects the stale **77**), one bundle later (expects **1**), and finally swaps/copies registers in one bundle to
check parallel reads. Making loads land one bundle early makes that test fail.

Notice what the unrolled version costs: it executes *fewer operations* and more per cycle, but the program is longer and fits only machines with
exactly this latency and slot mix.

## Run it

```bash
make test T=vliw4
```

## Exercises

1. **Software-pipeline** the loop so the memory slot is busy every cycle. Each element needs 2 loads + 1 store = 3 memory operations, so one memory slot
   bounds the kernel at 3 bundles per element *however far you unroll*; PROG 2 reaches 3.5 because of loop-carried latency and overhead. Can you reach 3.0?
2. Add a second memory slot and recompute the best schedule -- which resource is the bottleneck now?
3. Add **predication** (a predicate register per operation) so short `if`s need no branch.
4. Add branch **delay slots** (exposed branch latency) and schedule useful work in them.
5. Write the same kernel for [`tomasulo_rob`](../../ch03_ilp/tomasulo_rob) and compare cycles on a machine that finds the parallelism itself.
