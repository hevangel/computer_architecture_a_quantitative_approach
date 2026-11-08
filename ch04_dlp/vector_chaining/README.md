# Vector Chaining: Convoys, Chimes and Element-Level Forwarding

**Topic:** Chapter 4 (Data-Level Parallelism) and the vector appendix · **Editions:** 1-7 (the chime/convoy analysis is the book's performance model for vector processors) ·
**Files:** [`sv/vector_chain.sv`](sv/vector_chain.sv), [`vhdl/vector_chain.vhd`](vhdl/vector_chain.vhd)

## Background

[`vector_lanes`](../vector_lanes) shows *how many elements per cycle* a vector unit retires. This example adds the other half of vector performance:
**when can dependent instructions overlap?** Real vector units are deeply pipelined, so a vector instruction costs `start-up latency + VL` cycles. If
every instruction had to wait for its predecessor to finish completely, DAXPY

```
LV     V1, [X]          ; load X
MULVS  V2, V1, a        ; a * X
LV     V3, [Y]          ; load Y
ADDV   V4, V2, V3       ; a*X + Y
SV     V4, [Y]          ; store
```

would take roughly five times `VL`. **Chaining** forwards each result *element* to the dependent instruction as soon as it is written, exactly like
register forwarding in the scalar pipeline, so the dependent instruction starts one pipeline latency after its producer instead of one vector after it.
Instructions that can run together form a **convoy**, and the book measures time in **chimes** (one convoy = one chime); a sequence of *m* convoys
takes about `m x VL` cycles plus start-up costs. Structural hazards split convoys: here there is **one memory pipe**, so the second `LV` cannot join the
first convoy, which gives three convoys for DAXPY: `{LV, MULVS}`, `{LV, ADDV}`, `{SV}`.

## Design

Three pipelined units, one element per cycle each: **MEM** (`LV`/`SV`), **ADD** (`ADDV`, `SUBV`, `ADDVS`) and **MUL** (`MULV`, `MULVS`), with
latencies LD 6, ADD 4, MUL 7 (a store takes 1). Vector length `vl` is fixed while a program runs.

* **Issue:** in order, one instruction per cycle. An instruction issues when its unit is free (the previous instruction on that unit has sent its last
  element in, or is doing so this cycle) and its destination has **no pending writer** (WAW) and **no unfinished reader** (WAR). The destination must differ
  from the sources.
* **Per-element RAW:** every register has `avail`, the number of valid elements (reset to 0 when a writer issues, incremented as elements are written).
  Element *i* of a consumer may enter its unit only when `avail > i` for each source. That is **chaining**: with `CHAIN = 1` a consumer element can follow
  the producer element one cycle after it was written. With `CHAIN = 0`, `avail` jumps to `vl` only when the whole vector has been written.
* A result element appears in the register file `LAT` cycles after it entered the unit (a short delay line per unit).

Resulting rules for an instruction *k* (first issue = cycle 0, `d` = issue cycle, `s` = cycle its first element enters, `VL` = vector length):

```
d_k >= d_(k-1) + 1                                   in-order issue
d_k >= s_j + VL - 1                j on the same unit                       unit free
d_k >= s_j + VL - 1 + LAT_j        j writes the destination of k            WAW
d_k >= s_j + VL                    j reads the destination of k             WAR
s_k >= d_k + 1
s_k >= s_j + LAT_j                 j produced a source of k, chained        RAW
s_k >= s_j + VL - 1 + LAT_j        same, not chained
```

## Verification

**Directed: DAXPY with schedules derived by hand** (the testbench also confirms that the closed-form rules above reproduce these numbers):

| VL | mode | issue cycles `d` | start cycles `s` | machine idle at |
|---:|------|------------------|------------------|----------------:|
| 16 | chained   | 0 1 16 17 32 | 1 7 17 23 33  | 49 |
| 16 | unchained | 0 1 16 17 32 | 1 22 17 44 63 | 79 |
|  8 | chained   | 0 1 8 9 16   | 1 7 9 15 19   | 27 |
|  8 | unchained | 0 1 8 9 16   | 1 14 9 28 39  | 47 |
|  1 | either    | 0 1 2 3 4    | 1 7 3 14 18   | 19 |

For VL = 16 the chained run takes 49 cycles, about 3 convoys x 16, against 79 unchained (1.61x). With VL = 1 chaining changes nothing.

**Random programs:** 40 programs of 12 instructions (random operations, registers 0-5, vector length 1-16, bases and scalars) per configuration. For each one the
issue and start cycle of every instruction and the idle cycle are compared with the closed-form schedule, and all eight vector registers and all 256 memory
words with a sequential interpreter (32-bit wrap-around arithmetic). The chained machine needs 3804 cycles in total for the 40 programs, the unchained 4225.

Mutation spot checks (each makes the testbench fail; the SystemVerilog design was mutated in all five ways, the VHDL design in the first three): an off-by-one in the element-availability test, dropping the WAR check, letting a
non-chained machine publish elements early, shortening a unit latency, and not releasing a unit when its last element enters. Both languages end at the same simulated time.

## Run it

```bash
make test T=vector_chaining
```

## Exercises

1. Add a second memory pipe (an independent `LV` unit) and show that DAXPY then needs two convoys.
2. Replace the "destination differs from sources" rule with in-place operation (`ADDVS V1, V1, s`) by letting a unit read element *i* before the same
   element is overwritten.
3. Add `L` lanes (see [`vector_lanes`](../vector_lanes)): each unit then moves `L` elements per cycle, and the convoy time becomes `ceil(VL/L)`.
4. Add strip-mining control for `VL > MVL` and compare the total time for a 100-element DAXPY with the formula `ceil(n/MVL) x (T_loop + T_start) + n x T_chime`.
5. Add **flexible chaining** (a consumer may chain to *any* in-flight producer, even one that started later than the consumer's earlier source).
