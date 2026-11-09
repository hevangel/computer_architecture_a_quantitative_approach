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
| [`scoreboard`](scoreboard) | CDC 6600 scoreboard: RAW / WAR / WAW / structural stalls, no renaming |
| [`tomasulo_spec`](tomasulo_spec) | Tomasulo + speculation: branch prediction, commit-time flush, wrong-path safety |
| [`tomasulo_lsq`](tomasulo_lsq) | + load/store queue: stores at commit, memory disambiguation, store-to-load forwarding |
| [`tomasulo_rob`](tomasulo_rob) | reservation stations, CDB, renaming, reorder buffer; out-of-order completion, in-order commit |

Planned: tournament predictor and BTB, dual-issue
superscalar (see [`docs/roadmap.md`](../docs/roadmap.md)).
