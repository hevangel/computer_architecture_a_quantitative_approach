# Fixed-point DSP MAC, circular addressing and repeat

**Topic:** Embedded DSP datapaths · **Editions:** 3–7 · **Files:** [SystemVerilog](sv/dsp_qmac_circular_zoloop.sv), [VHDL](vhdl/dsp_qmac_circular_zoloop.vhd)

## Background

DSPs combine multiply-accumulate arithmetic with address generators and repeat mechanisms to reduce FIR loop overhead. See Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 5th edition (2011), Appendix E §E.2. This is an original teaching datapath, not an implementation of a particular DSP instruction set.

## Design

Signed Q1.15 operands form a Q2.30 product and accumulate into a signed 40-bit Q10.30 register, saturating on each overflow. Conversion to Q1.15 uses round-to-nearest, ties-to-even, followed by signed 16-bit saturation. `mac_clear` takes precedence over `mac_enable`. A four-bit circular pointer increments modulo a caller-supplied 1–16 modulus; its loaded start must be below the modulus. Modulus zero or above 16 disables stepping. A fixed four-bit reversal maps FFT indices for 16 points. A separately loaded five-bit repeat counter exposes active and last signals and decrements on `repeat_step`; zero never underflows. The caller controls sample memory and drives the MAC, pointer and repeat step signals together; there is no instruction decoder or autonomous FIR controller.

## Verification

Both testbenches execute 16 MACs starting at pointer 13 and wrapping through the complete delay line, with one repeat step per tap and no loop branch. The exact accumulator is 503,316,480 and the rounded result is 15,360. They check all 16 FFT index permutations, positive and negative half-way rounding ties, and both 40-bit accumulator and 16-bit output saturation. The independent Python `Fraction` reference checks these expected results. Both simulations pass at 10,770 ns; Verilator lint passes.

## Run it

```sh
python appE_embedded/dsp_qmac_circular_zoloop/check_reference.py
python scripts/run_tests.py -v dsp_qmac_circular_zoloop
```

## Exercises

1. Add autonomous sample and coefficient memories and compare a streaming FIR against a software convolution.
2. Add a programmable circular base and stride.
3. Extend the bit-reversal generator to variable power-of-two FFT sizes.
