# Dual-Issue In-Order RV32I Pipeline

**Topic:** Static scheduling and multiple issue · **Edition:** 6th edition, Chapter 3 §3.7 · **Files:** [SystemVerilog](sv/superscalar_dual_issue.sv), [VHDL](vhdl/superscalar_dual_issue.vhd)

## Background

A multiple-issue pipeline can execute independent instructions together when execution resources and dependencies permit it. A compiler or hand schedule can move independent work between a load and its consumer to avoid a stall. These original teaching implementations illustrate the cited section; their supported instruction set is deliberately limited.

## Design

The five stages are fetch, decode/issue, execute, memory and write-back. A fetch supplies two consecutive 32-bit instructions. One execution lane handles ALU operations and branches; the other handles ALU operations and word loads/stores. A lone memory instruction is routed to the memory lane. The issue logic serializes pairs with a cross-instruction RAW or WAW dependency, two memory operations, a branch or `EBREAK`; WAR pairs are allowed. If only one instruction issues, the second is retained for the next cycle.

The implementation supports `ADD`, `SUB`, `ADDI`, `LUI`, `LW`, `SW`, `BEQ`, `BNE`, and `EBREAK`. It forwards results from both execution lanes at the later pipeline stages, stalls for an immediately preceding load dependency, and squashes younger instructions when a branch resolves taken in execute. Memories have combinational reads and one-cycle writes. There are no traps, alignment checks, caches, multiply instructions, or complete RV32I decoding; unsupported encodings must not be executed. The counters report cycles, retired instructions, issued pairs, load stalls, and taken-branch flushes, and freeze when `EBREAK` retires.

## Verification

Both testbenches run the same programs on this core and on the existing [`rv32i_pipeline5`](../../appC_pipelining/rv32i_pipeline5), comparing all registers, all 64 data-memory words and retired counts after each run. Directed tests include pair dependencies, load-use stalls, write-after-write ordering, a backward loop, and wrong-path register, memory and halt operations. A further seeded 180-instruction mix checks arithmetic, loads and stores. Both language simulations finish at the same time.

The scheduled and unscheduled programs unroll 23 iterations of a dot product with coefficients `+1` and `-1`: `sum(a[i] - a[i+1])`, where the eight input values are the squares 1 through 64. Both give **−63** and identical full architectural state. The scheduled program retires 186 instructions in **98 cycles** (IPC ≈ **1.90**); the unscheduled program takes **144 cycles** (IPC ≈ **1.29**). These figures describe the stated ideal-memory test, not a general processor speedup.

## Run it

```sh
python scripts/run_tests.py -v superscalar_dual_issue
```

## Exercises

1. Extend decoding and exception handling to the rest of RV32I.
2. Add memory stalls, misaligned-access handling and a realistic instruction fetch interface.
3. Explore branch prediction and allowing independent work to issue when only one candidate has a load dependency.
