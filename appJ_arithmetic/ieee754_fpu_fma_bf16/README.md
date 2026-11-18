# Binary32 and Low-Precision FMA

The [SystemVerilog](sv/ieee754_fpu_fma_bf16.sv) and [VHDL](vhdl/ieee754_fpu_fma_bf16.vhd) designs use an exact 1,112-bit fixed-point datapath before rounding. Operation codes 0, 1 and 2 select add, multiply and FMA. For FMA, format codes 0–3 select binary32, BF16, E5M2 and E4M3FN. Low-precision inputs occupy the low bits of the operand ports and accept signed eight-bit power-of-two scale exponents. The addend is always binary32. Rounding codes 0–3 select RNE, RTZ, RUP and RDN. The guard bit and the OR of all lower bits retain the information needed for rounding.

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 7th edition (2025), Appendix J §§J.3–J.7 and Chapter 7. This model and its tests are original implementations.

## Model

[`fp_reference.py`](python/fp_reference.py) decodes binary32 into exact rational numbers, computes add, multiply and fused multiply-add without intermediate rounding, then encodes a binary32 result. It supports round-to-nearest ties-to-even, toward zero, toward positive infinity and toward negative infinity. It returns the five-bit `NV DZ OF UF NX` exception mask. Divide-by-zero is never raised by these three operations. Tininess is detected after rounding; inexact tiny results raise both underflow and inexact. NaNs are canonicalized, with signaling NaNs raising invalid. Invalid infinity/zero and infinity cancellation cases also raise invalid. Exact zero signs follow operand signs and rounding direction.

BF16, E5M2 and finite-only E4M3FN inputs can be expanded exactly to binary32 or fed to a scaled FMA. The scaled operation applies integer power-of-two input scales to the exact decoded operands and rounds once at the final binary32 result; it is a defined teaching model, not a claim to reproduce a particular hardware vendor's intermediate scaling or NaN policy. E5M2 supports infinities and signaling NaNs; E4M3FN has finite values through ±448 and one NaN encoding per sign.

## Verification

The Python tests cover directed rounding and ties, signed zero, exact and inexact subnormals, underflow after rounding, overflow, NaNs, infinities and a fused cancellation example. All 256 encodings of each FP8 format are checked against independently calculated numeric values. A deterministic 4,000-pair comparison checks binary32 add and multiply results against binary64 host arithmetic followed by binary32 packing, using ranges chosen to avoid intermediate precision loss.

```sh
python -m unittest discover -s appJ_arithmetic/ieee754_fpu_fma_bf16/python -v
```

## Hardware verification

Both HDL testbenches use the same 7,156 vectors. Regenerate them from the exact Python model and run both testbenches from the repository root.

```sh
python appJ_arithmetic/ieee754_fpu_fma_bf16/python/generate_vectors.py
python scripts/run_tests.py -v ieee754_fpu_fma_bf16
```

The wide combinational implementation prioritizes clarity. Synthesis, area and timing remain unverified.

## Exercises

1. Compare a fused calculation with a separately rounded multiply and add when the product nearly cancels the addend. Report the resulting encodings and flags.
2. Use a smaller alignment window with sticky-bit tracking. Compare its result and flags against the shared vector suite before measuring area and timing.
