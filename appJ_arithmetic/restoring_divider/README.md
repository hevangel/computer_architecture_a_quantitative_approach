# Restoring Divider

**Topic:** Appendix J (Computer Arithmetic) · **Editions:** 1-7 (arithmetic appendix) ·
**Files:** [`sv/restoring_divider.sv`](sv/restoring_divider.sv), [`vhdl/restoring_divider.vhd`](vhdl/restoring_divider.vhd)

## Background

Binary long division produces one quotient bit per step. Each step shifts the partial remainder left, brings
down the next dividend bit, and asks whether the divisor fits:

```
for i = N-1 downto 0:
    R = (R << 1) | dividend[i]
    if R >= D:  R = R - D;  Q[i] = 1
    else:                   Q[i] = 0          # the trial subtraction is "restored" (discarded)
```

This is the **restoring** algorithm; the textbook then improves it to *non-restoring* and *SRT* division, which
avoid the restore step and generate several quotient bits per cycle. Division is far slower than
multiplication, which is why it is often not fully pipelined.

## Design

An unsigned 16 / 16 divider, one quotient bit per clock:

* A 17-bit remainder register makes the trial subtraction's sign visible (`diff[16]`).
* The dividend shifts out of `n` bit by bit while the quotient shifts into `q`.
* **16 cycles** after `start`, `done` is high with `quotient` and `remainder` valid.
* **Divide by zero** follows the RISC-V convention: quotient = all ones, remainder = dividend. (No special case is coded:
  with `D = 0` every trial subtraction "succeeds", so every quotient bit is 1, and the remainder register just
  accumulates the dividend bits.)

## Verification

Directed cases (`0/1`, `1/1`, `100/7`, `65535/1`, `65535/65535`, `5/9`, `32768/3`, `65535/2`, `1234/0`, `0/0`)
plus **2 000 random** pairs, a quarter of which use a small 8-bit divisor to get long quotients. Quotient and
remainder are compared with the language's `/` and `%`, and every operation must take exactly 16 cycles.

## Run it

```bash
make test T=restoring_divider
```

## Exercises

1. Convert to **non-restoring** division and compare the critical path.
2. Add signed division with the RISC-V rounding rules (`div`/`rem`).
3. Process two quotient bits per cycle (radix-4) and measure the latency/area trade-off.
