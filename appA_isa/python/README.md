# ISA classes and traffic

`isa_class_traffic.py` interprets original toy stack, accumulator,
register-memory and load-store instruction streams, alongside encoded RV32IM and
classic MIPS64 subsets interpreted by `rv32im_traffic.py` and `mips64_traffic.py`.
Each runs the same addition, arithmetic expression and unrolled adjacent-comparison sort. It reports executed
instructions, static and dynamic encoded instruction bytes, and memory read and
write bytes. Run the sample report and tests from the repository root:

```sh
python appA_isa/python/isa_class_traffic.py
python -m unittest discover -s appA_isa/python -p 'test_*.py' -v
```

The four toy ISAs have explicit hypothetical encoding lengths in `SIZES`; they
are not historical instruction sets. The RV32IM variant encodes and decodes LW,
SW, ADD, SUB, MUL, BGE and EBREAK as 32-bit words. It models signed comparison,
32-bit wraparound, x0 and aligned word accesses, but no other instructions,
traps or timing. Its multiplication uses the M extension and is not RV32I alone.
The classic MIPS64 variant models LD, SD, DADDU, DSUBU, DMULT, MFLO, SLT, BEQ,
NOP and BREAK, including a branch delay slot, signed comparison and multiplication,
HI/LO, 64-bit wrapping, and aligned eight-byte loads and stores. The branch delay
slot differs from the intentionally delay-slot-free pipeline example in this repository.
It does not model other instructions, traps, pipeline timing or later ISA revisions.
The addition programs reproduce the operand conventions of Hennessy and Patterson, 5th edition (2011), Appendix A, Figures A.1–A.2, PDF p. 527. The 1st edition (1990), Chapter 3, Figure 3.3, PDF p. 122, shows the first three classes. Excluding the interpreter's halt instruction, the stack, accumulator, register-memory and load-store bodies use 4, 3, 3 and 4 instructions. They each read A and B and write C: 12 external data bytes with four-byte words and an internal stack. The toy encoding assumptions make their body sizes 10, 9, 12 and 16 bytes; these byte lengths are not specified by the textbook figure. Encoded RV32IM and MIPS64 use 16 body bytes, but their data traffic differs because this MIPS64 example uses eight-byte words.

For other workloads, counts are synthetic and are not textbook measurements. By default every stack push and pop accesses a four-byte memory word. For the internal-stack comparison, pass `stack_storage="internal"`; this idealized mode counts no spill traffic and does not model finite stack capacity. Register and accumulator accesses do not generate data-memory traffic. Instruction
traffic is reported separately. Sort comparisons are unrolled, while conditional
swaps make dynamic counts depend on the input. Scratch space is distinct from
input data. Arithmetic uses unbounded Python integers, without overflow, caches,
alignment, exceptions, or cycle timing in the toy machines. These choices permit controlled comparisons
but do not establish real-system performance.

Tests check all 24 permutations of four distinct values, repeated and negative values, and hand-counted traffic examples. The RV32IM and MIPS64 tests also check literal instruction words, signed branches, register zero, negative offsets and wraparound. MIPS64 tests cover taken delay slots and HI/LO multiplication. The sort traffic counts are for the synthetic unrolled programs, not a reproduction of a textbook benchmark measurement.
