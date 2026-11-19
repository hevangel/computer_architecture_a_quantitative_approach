# Appendix C -- Pipelining: Basic and Intermediate Concepts

The five-stage RISC pipeline (IF, ID, EX, MEM, WB) and its hazards -- structural, data and control. Pipelining
raises throughput by overlapping instructions but does not shorten any one instruction's latency; the cost is
hazard logic. In the first two editions this was a main chapter; from the 3rd it is an appendix.

## Examples

| Example | ISA | Editions using that ISA |
|---------|-----|-------------------------|
| [`multicycle_microcode_baseline`](multicycle_microcode_baseline) | hardwired FSM and ROM sequencer on one RV32I datapath | 1, 6–7 |
| [`r4000_superpipeline8`](r4000_superpipeline8) | R4000-style eight-stage MIPS64 timing and optional branch delay slot | 5–7 |
| [`rv32i_precise_exceptions`](rv32i_precise_exceptions) | simultaneous faults, CSR handler and precise restart | 1, 5–7 |
| [`rv32i_pipeline5`](rv32i_pipeline5) | RISC-V RV32I (branches resolved in EX, 2-cycle penalty) | 6-7 |
| [`mips_pipeline5`](mips_pipeline5) | DLX / MIPS32 (`XLEN=32`) and MIPS64 (`XLEN=64`) (branches resolved in ID, 1-cycle penalty) | 1-2 (DLX), 3-5 (MIPS64) |

Planned: an unpipelined multicycle baseline
for the speedup comparison; a pipelined floating-point unit (see [`docs/roadmap.md`](../docs/roadmap.md)).
