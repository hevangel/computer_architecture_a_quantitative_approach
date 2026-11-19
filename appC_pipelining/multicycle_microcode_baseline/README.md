# Hardwired and Microcoded Multicycle RV32I Baseline

**References** — Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 1st edition (1990), Chapter 5 §§5.3–5.7, and 6th edition (2017), Appendix C §C.1.

A single datapath fetches and decodes an instruction, executes it, and commits it before entering the next fetch. The hardwired configuration uses a state machine. The microcoded configuration uses a micro-PC and a ROM whose word contains datapath enables, the next microaddress, and a conditional load dispatch bit. Both configurations use four cycles for arithmetic, control, stores and the terminating EBREAK. Loads take an additional memory-read cycle. The implementation uses the same word load and store, ALU and control-flow subset as the five-stage teaching core. It assumes combinational instruction and data reads and omits memory waits and traps.

The checked-in 25-word image matches the original five-stage pipeline test's assembled instruction stream. Both testbenches attach that image and separate zeroed data memories to a hardwired core, a microcoded core and the existing five-stage core. They check matching hardwired and microcoded PC, timing, store and retirement traces, then compare every register and memory word across the three cores. Each retires 49 instructions and writes exactly two words. The multicycle cores finish in 197 cycles and the pipeline finishes in 78, a measured CPI ratio of approximately 2.53 on this program.

```sh
python appC_pipelining/multicycle_microcode_baseline/python/generate_program.py
python scripts/run_tests.py -v multicycle_microcode_baseline
```

## Exercises

1. Extend the ROM word with a selectable branch on an ALU flag and write an alternative microprogram for loads.
2. Add memory stalls to both controllers and compare precise store timing under backpressure.
