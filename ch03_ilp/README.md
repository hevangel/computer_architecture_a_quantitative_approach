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
| [`tage_predictor`](tage_predictor) | tagged geometric histories, usefulness and gshare comparison |
| [`spectre_transient_demo`](spectre_transient_demo) | bounds speculation, an abstract cache footprint and a delaying mitigation |
| [`branch_predictor`](branch_predictor) | 1-bit, 2-bit and gshare predictors on the same trace |
| [`tournament_btb_ras`](tournament_btb_ras) | local/global tournament prediction, target buffer and return stack |
| [`scoreboard`](scoreboard) | CDC 6600 scoreboard: RAW / WAR / WAW / structural stalls, no renaming |
| [`smt_multithread_core`](smt_multithread_core) | two-thread renaming and four issue policies with shared execution resources |
| [`prf_rename_ooo`](prf_rename_ooo) | physical register file, rename maps, free list and precise branch recovery |
| [`tomasulo_mem_spec_replay`](tomasulo_mem_spec_replay) | speculative loads, violation replay and resolve-time branch recovery |
| [`superscalar_dual_issue`](superscalar_dual_issue) | two-wide in-order RV32I subset with dependency checking and forwarding |
| [`tomasulo_spec`](tomasulo_spec) | Tomasulo + speculation: branch prediction, commit-time flush, wrong-path safety |
| [`tomasulo_lsq`](tomasulo_lsq) | + load/store queue: stores at commit, memory disambiguation, store-to-load forwarding |
| [`tomasulo_rob`](tomasulo_rob) | reservation stations, CDB, renaming, reorder buffer; out-of-order completion, in-order commit |

Planned: dual-issue superscalar and further work in [`docs/roadmap.md`](../docs/roadmap.md).
