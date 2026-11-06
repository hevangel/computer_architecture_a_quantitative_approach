# Appendix H -- Hardware and Software for VLIW and EPIC

The software school of ILP: the compiler packs independent operations into one long instruction word, and the
hardware simply issues it. Techniques: loop unrolling, software pipelining, trace scheduling, predication, and (in
Itanium/EPIC) rotating registers and speculative loads. Prominent in the 3rd and 4th editions' main text.

## Examples

| Example | What it shows |
|---------|---------------|
| [`vliw4`](vliw4) | 4-slot bundles, exposed latencies, no interlocks; one DAXPY kernel scheduled three ways (IPC 1.01 / 1.77 / 1.94) |

Planned: software-pipelined loop, predication, delayed branches (see [`docs/roadmap.md`](../docs/roadmap.md)).
