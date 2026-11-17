# Banked vector memory and strip-mining

**Topic:** vector memory systems · **Editions:** 1–7 · **Files:** [SystemVerilog](sv/vector_bank_gather_strip.sv), [VHDL](vhdl/vector_bank_gather_strip.vhd)

## Background

Vector memories interleave words across banks so independent accesses can proceed in parallel. A stride sharing factors with the bank count can serialize those accesses; strip-mining splits a longer vector into chunks fitting the vector register length. See Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Chapter 4 §4.2 and Appendix G §§G.2–G.4. This original teaching model is not an RVV implementation.

## Design

The model holds 512 32-bit words mapped by low three address bits to eight single-port banks. Up to 16 pending lanes form a strip. Each bank grants its lowest-numbered pending lane once per cycle; lanes continue until the strip completes, then the next strip starts. Linear accesses use a base and unsigned stride; indexed gather/scatter uses a host-loaded index table. Addresses wrap modulo 512. Duplicate scatter addresses serialize in increasing lane order, so the last lane wins. Host memory and vector table writes are accepted only while idle. Results are read by selecting a vector slot. Inputs are captured at start; a command accepts 0–64 elements, with longer commands rejected, so unbounded vector lengths require a higher-level driver.

`service_cycles` counts active bank service cycles, `ideal_cycles` sums ceil(strip length/8), and `bank_stalls` is their difference at completion. `strips` and `strip_length` expose strip progress. These counts do not include host setup, bank recovery delay or startup; `bank_stalls` is meaningful after `done`, since the ideal total is accumulated at strip start. The independent [Python reference](../python/vector_memory_reference.py) models the same bank schedule and provides idealized R-infinity and N-half calculations when startup is supplied. It does not establish measured physical performance.

## Verification

Both testbenches check 45 unit-stride words split 16+16+13 in six service cycles with no conflict stalls. Sixteen stride-8 words use one bank and require 16 cycles versus two ideal cycles. A sparse 45-element scatter and gather each take seven cycles, with all values verified; duplicate stores, 64-element commands, empty commands and rejected oversized commands are also checked. Both simulations passed at 2,540 ns, the Python reference tests passed, and Verilator lint passed.

## Run it

```sh
python scripts/run_tests.py -v vector_bank_gather_strip
python -m unittest discover -s ch04_dlp/python -p 'test_*.py'
```

## Exercises

1. Stream indices and results to support arbitrarily long commands.
2. Add multi-cycle bank recovery and compare different strides.
3. Add vector masks and concurrent independent requests.
