# Amdahl's Law

**Topic:** Chapter 1 (Fundamentals of Quantitative Design and Analysis) · **Editions:** 1-7 ·
**Files:** [`sv/amdahl_speedup.sv`](sv/amdahl_speedup.sv), [`vhdl/amdahl_speedup.vhd`](vhdl/amdahl_speedup.vhd)

## Background

The quantitative approach starts with one observation: an improvement can only speed up the part of a
program that uses it. If a fraction *f* of the original execution time benefits from an enhancement that
makes that fraction *s* times faster, then

```
                  1                       1
Speedup  =  -----------------  =  ------------------
            (1 - f) + f / s        Execution_time_new / Execution_time_old
```

Two consequences shape every design decision in the book:

* **There is a hard ceiling.** Even with an infinitely fast enhancement (`s -> infinity`) the speedup is
  `1 / (1 - f)`. Speeding up 90 % of a program can never give more than 10x.
* **Diminishing returns.** With `f = 0.9` an enhancement of `s = 10` gives 5.26x, but `s = 100` only 9.17x.

Worked values used by the test:

| f | s | Speedup |
|---|---|---------|
| 0.80 | 10  | 3.5714 |
| 0.50 | 2   | 1.3333 |
| 0.90 | 100 | 9.1743 |
| 0.95 | 16  | 9.1429 |
| 0    | any | 1.0 (nothing to accelerate) |
| 1    | 8   | 8.0 (everything accelerated) |

## Design

A purely combinational unit in fixed point:

| Signal | Format | Meaning |
|--------|--------|---------|
| `f_q16` | Q1.16 unsigned, 17 bits (65536 = 1.0) | fraction enhanced |
| `s_q8_8` | Q8.8 unsigned, 16 bits (256 = 1.0) | speedup of the fraction |
| `speedup_q16` | Q16.16 unsigned, 32 bits | overall speedup |

It computes `(1 - f)`, then `f / s` (one integer divide), sums them, and takes the reciprocal with a second
divide (`2^32 / denominator`). Dividers are expensive in hardware -- see
[`appJ_arithmetic/restoring_divider`](../../appJ_arithmetic/restoring_divider) for a sequential one -- so
this is a *model* of the law, not an area-efficient implementation. `s = 0` is invalid and returns 0.

## Verification

Both testbenches drive the cases in the table above plus `s = 0`, and compare with reference values computed
offline with exact rational arithmetic. The tolerance is 128 LSBs (about 0.002) because `f` is quantized to
1/65536.

## Run it

```bash
make test T=amdahl            # SystemVerilog (iverilog) and VHDL (ghdl)
```

## Exercises

1. Extend the unit to take two enhancements `(f1, s1)` and `(f2, s2)` with `f1 + f2 <= 1`.
2. Add a "break-even" output: the minimum `s` needed for a target overall speedup.
3. Replace the combinational divides with the sequential divider from Appendix J.
