# Appendix C -- Pipelining: Basic and Intermediate Concepts

The five-stage RISC pipeline (IF, ID, EX, MEM, WB) and its hazards -- structural, data and control. Pipelining
raises throughput by overlapping instructions but does not shorten any one instruction's latency; the cost is
hazard logic. In the first two editions this was a main chapter; from the 3rd it is an appendix.

## Examples

| Example | ISA | Editions using that ISA |
|---------|-----|-------------------------|
| [`rv32i_pipeline5`](rv32i_pipeline5) | RISC-V RV32I | 6-7 |

Planned: the same pipeline for DLX (1st-2nd editions) and MIPS64 (3rd-5th); an unpipelined multicycle baseline
for the speedup comparison; a pipelined floating-point unit (see [`docs/roadmap.md`](../docs/roadmap.md)).
