# Predicated and Software-Pipelined VLIW

**Reference** — Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Appendix H §§H.3–H.5.

The four slots keep the original bundle's two ALUs, memory unit and control unit. The opcode and register fields stay in the upper 16 bits. The lower field now contains the predicate index in bits 15–13, an invert bit at 12 and a signed 12-bit immediate. Predicate p0 is always true. PSET writes another predicate from an equality or inequality comparison. Every slot sees the prior bundle's predicate and register values.

A faulting LD.S produces a NaT-marked value after the exposed two-bundle load delay. Integer operations propagate NaT. An enabled CHK.S stops the core with deferred trap cause 2 if its operand is marked. A false predicate suppresses the check and all other effects of its slot. Normal memory faults and stores that consume NaT stop the core with cause 1. A trapping bundle suppresses its effects while permitting the preceding load to land.

LD.A allocates a physical destination and four-byte address entry in a four-slot round-robin ALAT. Stores invalidate entries whose byte ranges overlap. Rewriting a tracked register also invalidates its entry. CHK.A falls through on a hit and branches to its immediate recovery address on a miss. A same-bundle overlapping store is visible to the check. The programming model assumes the exposed load delay and avoids conflicting register writes in one bundle.

ROTBR branches on a nonzero loop count and swaps the physical mappings of r8–r11 and r12–r15. The DAXPY schedule uses two rotating banks and a prologue, repeating three-bundle kernel and epilogue. In steady state it overlaps the current element's loads and multiply with the preceding element's addition and store. Both implementations compare all eight results against the original loop-unrolled VLIW core and the scalar result. The modulo schedule takes 29 bundles versus 31, including launch and drain. Raw IPC is 76/29 versus 60/31. Because the bookkeeping counts differ, the comparison also reports the same eight useful outputs over 29 versus 31 cycles. Tests cover a one-element run, a suppressed and an enabled NaT check, disjoint and overlapping stores, and ALAT replacement.

```sh
python appH_vliw/vliw4_swpipe_pred_alat/python/generate_programs.py
python scripts/run_tests.py -v vliw4_swpipe_pred_alat
```

## Exercises

1. Schedule conditional arithmetic and a store with complementary guards.
2. Add a recovery path that reloads the affected word and rejoins the kernel after CHK.A misses.
