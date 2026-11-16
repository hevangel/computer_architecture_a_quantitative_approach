# ISA classes and traffic

`isa_class_traffic.py` interprets original toy stack, accumulator,
register-memory and load-store instruction streams, alongside encoded RV32IM and
classic MIPS64 subsets interpreted by `rv32im_traffic.py` and `mips64_traffic.py`.
Each runs the same arithmetic
expression and an unrolled adjacent-comparison sort. It reports executed
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
All counts use synthetic workloads and are not textbook measurements. Every stack push and pop accesses a
four-byte word in memory; register and accumulator accesses do not. Instruction
traffic is reported separately. Sort comparisons are unrolled, while conditional
swaps make dynamic counts depend on the input. Scratch space is distinct from
input data. Arithmetic uses unbounded Python integers, without overflow, caches,
alignment, exceptions, or cycle timing in the toy machines. These choices permit controlled comparisons
but do not establish real-system performance.

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 6th edition (2017), Appendix A, instruction-set principles, and 1st
edition (1990), Chapters 3–4. Tests check all 24 permutations of four distinct
values, repeated and negative values, and hand-counted traffic examples. The
RV32IM and MIPS64 tests also check literal instruction words, signed branches,
register zero, negative offsets and wraparound. MIPS64 tests cover taken delay
slots and HI/LO multiplication. Textbook-specific comparisons remain unimplemented.
