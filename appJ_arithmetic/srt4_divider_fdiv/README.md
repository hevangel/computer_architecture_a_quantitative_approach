# Radix-4 SRT Division and Five Omitted Selection Cells

**References** — Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Appendix J §§J.6 and J.9. The selection-cell coordinates and carry-save truncation follow Alan Edelman, [*The Mathematics of the Pentium Division Bug*](https://math.mit.edu/~edelman/homepage/papers/pentiumbug.pdf), *SIAM Review* 39(1), 1997, §4 and Figure 4.1.

## Datapath

A start pulse accepts two unsigned 32-bit operands while the divider is idle. Nonzero operands are normalized independently, retaining their exponent difference. Each of 33 radix-4 cycles selects a signed digit in {−2, −1, 0, 1, 2} using the truncated divisor and the separately truncated carry-save words. A compressor combines the sum and carry with a signed divisor multiple, then shifts by two. The two quotient-prefix registers track Q and Q−1. Choosing a prefix and appending the appropriate two bits converts each redundant digit without a wide quotient carry propagation.

The core returns the signed Q64 mantissa and its exponent along with an exact integer quotient and remainder in correct mode. A final residual check corrects a one-unit quotient ambiguity. A zero numerator finishes immediately. A zero denominator returns all ones as the integer quotient and the numerator as remainder with `divide_by_zero` asserted. The remaining public status bits are `busy`, a one-cycle `done` and `fault_hit`.

## Fault model

The Python generator constructs a selection table by applying the valid digit intervals to each row and column. In the five affected columns it prefers the documented threshold where that digit is admissible under the model's truncation bounds. The fault option replaces the five documented +2 cells with 0. The affected pair 4,195,835 ÷ 3,145,727 reaches an omitted cell, after which the mantissa loses precision. The faulty mode demonstrates the omission mechanism. The table's overlap choices and out-of-envelope behavior are defined for this teaching implementation, so the resulting faulty mantissa need not match a particular Pentium stepping bit for bit. Faulty integer outputs are diagnostic.

## Verification

The HDL tests check 577 operand pairs against integer quotient and remainder from Python `divmod` and mantissa bits from the exact rational trace model. Both languages check the 33-cycle cadence, divide-by-zero, the affected pair and parity between modes for all tested cases that did not reach a hole. The Python tests also verify that the table modes differ in exactly five cells and check the remainder bound and precision on 2,036 positive operand pairs.

```sh
python appJ_arithmetic/srt4_divider_fdiv/python/generate_selection.py
python appJ_arithmetic/srt4_divider_fdiv/python/generate_vectors.py
python -m unittest discover -s appJ_arithmetic/srt4_divider_fdiv/python -v
python scripts/run_tests.py -v srt4_divider_fdiv
```

## Exercises

1. Choose different admissible overlap digits and compare the redundant traces and corrected integer results.
2. Replace the loaded ROM with a combinational decoder, then measure its area and latency in synthesis.
