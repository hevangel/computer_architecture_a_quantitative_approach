# R4000-Style Eight-Stage MIPS Pipeline

**Reference** — Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Appendix C §C.6.

This variant of the repository's MIPS teaching core separates IF, IS, RF, EX, DF, DS, TC and WB. IF reads the instruction word, IS latches it, and RF decodes and reads registers. EX computes the result and resolves transfers. DF presents the data address, DS carries the returned word, TC makes the load eligible for forwarding, and WB retires. The data port assumes fixed-latency combinational memory. TC models the load readiness boundary without a cache tag array or address translation. The core omits the optional floating-point unit, real cache misses and exceptions.

ALU results forward from DF onward. An immediate load consumer waits two cycles while the load occupies EX and DF. A taken transfer discards three younger stages. With the optional delay slot, the instruction in RF completes and the remaining two stages are flushed. A delayed JAL saves PC+8. A control transfer in a delay slot is outside the teaching subset.

The same MIPS64 trace runs on the five-stage baseline and both eight-stage modes. It uses a dependent doubleword load and add, an independent taken branch and a store. All three obtain the same expected 64-bit memory values. The no-delay models agree in every register. The delay-slot model additionally writes the designated slot register. The baseline finishes in 11 cycles, with one load bubble and one branch bubble. The eight-stage versions finish in 17 cycles, with two load bubbles and either three branch bubbles or two plus one retired delay-slot instruction. The short trace includes pipeline fill and drain. A separate trace checks that a taken branch preserves a delay-slot instruction stalled behind an older load.

```sh
python scripts/run_tests.py -v r4000_superpipeline8
```

## Exercises

1. Add tag-compare and alignment signals at TC and recover in instruction order.
2. Add a pipelined floating-point execution unit and test mixed integer and FP scheduling.
