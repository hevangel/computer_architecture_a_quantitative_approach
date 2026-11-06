# Radix-4 Booth Multiplier

**Topic:** Appendix J (Computer Arithmetic) · **Editions:** 1-7 (arithmetic appendix) ·
**Files:** [`sv/booth_multiplier.sv`](sv/booth_multiplier.sv), [`vhdl/booth_multiplier.vhd`](vhdl/booth_multiplier.vhd)

## Background

Shift-and-add multiplication produces one partial product per multiplier bit. **Booth recoding** uses the identity that a run of 1s
from bit *i* to bit *j* equals `2^(j+1) - 2^i`: one subtraction where the run starts and one addition just past
its end, so a long run of 1s needs only two operations instead of one per bit. **Radix-4 (modified) Booth** examines the multiplier two bits at a
time -- an overlapping triplet `(b[2i+1], b[2i], b[2i-1])` -- and halves the number of partial products, handling
two's-complement operands without any sign-correction step:

| `b[2i+1] b[2i] b[2i-1]` | Partial product |
|:---:|:---:|
| 000 | 0 |
| 001, 010 | +M |
| 011 | +2M |
| 100 | -2M |
| 101, 110 | -M |
| 111 | 0 |

```
product = sum over i = 0..7 of  (recoded digit_i) * M * 4^i
```

## Design

A sequential 16 x 16 -> 32-bit signed multiplier:

* `m` holds the sign-extended multiplicand and is shifted left by 2 each step; `q` holds `{multiplier, 0}` and is
  shifted right by 2 each step, so `q[2:0]` is always the current triplet.
* Each clock adds the selected partial product (`0`, `+/-m`, `+/-2m`) into the 32-bit accumulator `acc`.
* After **8 steps** (16 bits / 2) `done` goes high and `product = acc` is valid. A new multiplication starts
  when `start` is pulsed while idle.

## Verification

Ten corner cases (`0*0`, `1*1`, `-1*-1`, `32767*32767`, `-32768*-32768`, `-32768*32767`, `-32768*-1`,
`1234*-5678`, `-3*7`, `0x5555 * 0xAAAA`) plus **2 000 random signed pairs**. Every product is compared with the
language's own signed multiplier and every operation must take exactly **8 cycles** after `start`.

## Run it

```bash
make test T=booth_multiplier
```

## Exercises

1. Build the combinational version: 8 partial products summed by a **Wallace/carry-save tree**.
2. Extend to radix-8 Booth (needs a precomputed `3M`) and compare adder counts.
3. Add a signed/unsigned mode input to support both `mul` and `mulhu`.
