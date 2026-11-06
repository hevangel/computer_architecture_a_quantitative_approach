# Chapter 3 -- Instruction-Level Parallelism and Its Exploitation

Pipelining (Appendix C) overlaps instructions; ILP techniques try to push CPI **below** 1 by issuing several
instructions per cycle. Two schools: **hardware** schemes find the parallelism at run time (dynamic scheduling,
speculation), **software** schemes find it at compile time (VLIW). The 2nd edition expanded this material and the
3rd split it into one chapter per school.

Key mechanisms: branch prediction, register renaming, dynamic scheduling (scoreboard, Tomasulo), speculation with a
reorder buffer, multiple issue.

## Examples

| Example | What it shows |
|---------|---------------|
| [`branch_predictor`](branch_predictor) | 1-bit, 2-bit and gshare predictors on the same trace |

Planned: scoreboard (CDC 6600), Tomasulo with a reorder buffer, tournament predictor and BTB, dual-issue
superscalar (see [`docs/roadmap.md`](../docs/roadmap.md)).
