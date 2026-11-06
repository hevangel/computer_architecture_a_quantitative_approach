# Appendix H -- Hardware and Software for VLIW and EPIC

The software school of ILP: the compiler packs independent operations into one long instruction word, and the
hardware simply issues it. Techniques: loop unrolling, software pipelining, trace scheduling, predication, and (in
Itanium/EPIC) rotating registers and speculative loads. Prominent in the 3rd and 4th editions' main text.

## Status

Empty so far -- see [`docs/roadmap.md`](../docs/roadmap.md). The first planned example is a 4-slot VLIW core with
a small assembler-as-functions testbench, run on the same DAXPY kernel as [`vector_lanes`](../ch04_dlp/vector_lanes).
