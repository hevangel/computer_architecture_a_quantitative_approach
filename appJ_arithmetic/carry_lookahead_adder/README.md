# Carry-Lookahead Adder

**Topic:** Appendix J (Computer Arithmetic) · **Editions:** 1-7 (arithmetic appendix) ·
**Files:** [`sv/carry_lookahead_adder.sv`](sv/carry_lookahead_adder.sv), [`vhdl/carry_lookahead_adder.vhd`](vhdl/carry_lookahead_adder.vhd)

## Background

A **ripple-carry** adder is built from chained full adders; the carry must travel through every bit, so delay
grows linearly with the word width. A **carry-lookahead adder (CLA)** computes all the carries in parallel from
two per-bit signals:

```
generate    g_i = a_i & b_i          this bit creates a carry by itself
propagate   p_i = a_i ^ b_i          this bit passes an incoming carry along

c_{i+1} = g_i | (p_i & c_i)
```

Unrolling the recurrence gives each carry directly from the inputs, e.g.

```
c1 = g0 | p0 c0
c2 = g1 | p1 g0 | p1 p0 c0
c3 = g2 | p2 g1 | p2 p1 g0 | p2 p1 p0 c0
```

and the sum is `s_i = p_i ^ c_i`. The fan-in of the unrolled terms grows quickly, so wide adders use **groups**:
each 4-bit group also exports a group generate `G` and group propagate `P`, and the same lookahead equations are
applied one level up across groups.

## Design

* `cla4_block` -- 4-bit adder with fully expanded in-block lookahead; outputs `sum`, `g_grp`, `p_grp`.
* `carry_lookahead_adder` -- 16 bits = four `cla4_block`s plus a second-level lookahead unit that produces the
  block carry-ins `c[1..3]` and `cout` from the group `G/P` and `cin`. No carry ripples between blocks.

The module is purely combinational; the point is the *structure* of the carry network.

## Verification

Seven corner cases (`0+0`, `FFFF+0+1`, `FFFF+FFFF+1`, `8000+8000`, `0001+FFFF`, `5555+AAAA+1`, a carry across one
nibble) followed by **20 000 pseudo-random** additions with random carry-in. Each result `{cout, sum}` is compared with
the language's own 17-bit addition. Both testbenches use the same LCG, so the two languages see the same stimulus.

## Run it

```bash
make test T=carry_lookahead
```

## Exercises

1. Extend to 64 bits with a third lookahead level.
2. Replace the first level with ripple blocks (a *carry-skip* or *carry-select* adder) and compare the structures.
3. Add a **carry-save adder** and build a multi-operand adder tree.
