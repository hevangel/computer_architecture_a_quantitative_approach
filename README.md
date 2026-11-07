# Computer Architecture: A Quantitative Approach -- in SystemVerilog and VHDL

Hardware implementations of the worked examples from Hennessy & Patterson's *Computer Architecture: A
Quantitative Approach*, from the 1st (1990) to the 7th (2025) edition. Every example is written **twice**,
in SystemVerilog and in VHDL, has a self-checking testbench in each language, and comes with a textbook-style
write-up (background, design, verification, exercises).

The goal is a book you can run: change a parameter, rerun the testbench, and watch the quantity the chapter
talks about -- a CPI, a miss rate, a speedup -- move.

## Quick start

Requires Python 3, [Icarus Verilog](https://github.com/steveicarus/iverilog) 12 (SystemVerilog), [GHDL](https://github.com/ghdl/ghdl) 4.x (VHDL),
and optionally [Verilator](https://www.veripool.org/verilator/) 5 (lint). On Ubuntu 24.04:

```bash
sudo apt-get install -y iverilog ghdl verilator
```

```bash
make test                    # run every example in both languages
make test T=cache            # only modules whose path contains "cache"
make test-sv                 # SystemVerilog only (also: make test-vhdl)
make list                    # list what was discovered
make lint                    # advisory Verilator lint of the SystemVerilog
```

A passing run ends with `40/40 passed`.

## What is in the box

| Chapter / appendix | Example | Shows |
|--------------------|---------|-------|
| [Ch 1 Fundamentals](ch01_fundamentals) | [`amdahl_speedup`](ch01_fundamentals/amdahl_speedup) | Amdahl's Law in fixed point |
| [Ch 2 Memory hierarchy](ch02_memory_hierarchy) | [`set_assoc_cache`](ch02_memory_hierarchy/set_assoc_cache) | set-associative write-back LRU cache with hit/miss counters |
| | [`tlb_walker`](ch02_memory_hierarchy/tlb_walker) | TLB + page-table walker, page and protection faults |
| [Ch 3 ILP](ch03_ilp) | [`branch_predictor`](ch03_ilp/branch_predictor) | 1-bit, 2-bit and gshare prediction (32 / 23 / 17 mispredicts of 60) |
| | [`scoreboard`](ch03_ilp/scoreboard) | CDC 6600 scoreboard: the four hazards as exact stall cycles |
| | [`tomasulo_spec`](ch03_ilp/tomasulo_spec) | Tomasulo + branch speculation: commit-time flush, loop 85 -> 76 cycles with a better predictor |
| | [`tomasulo_rob`](ch03_ilp/tomasulo_rob) | Tomasulo + reorder buffer: out-of-order completion, in-order commit, renaming |
| [Ch 4 DLP](ch04_dlp) | [`vector_lanes`](ch04_dlp/vector_lanes) | vector unit, DAXPY, `ceil(VL/lanes)` scaling |
| | [`simt_core`](ch04_dlp/simt_core) | GPU SIMT core: warps hide load latency (54 vs 72 cycles), divergence costs lane efficiency (0.77) |
| [Ch 5 TLP](ch05_tlp) | [`mesi_snoopy`](ch05_tlp/mesi_snoopy) | MESI snooping coherence, invariants under random traffic |
| [Ch 7 DSA](ch07_dsa) | [`systolic_array`](ch07_dsa/systolic_array) | TPU-style weight-stationary matrix unit |
| [App C Pipelining](appC_pipelining) | [`rv32i_pipeline5`](appC_pipelining/rv32i_pipeline5) | RISC-V 5-stage pipeline (branches in EX); CPI = 78/49 |
| | [`mips_pipeline5`](appC_pipelining/mips_pipeline5) | DLX / MIPS32 and MIPS64 5-stage pipeline (branches in ID); CPI = 84/53 |
| [App D Storage](appD_storage) | [`hamming_secded`](appD_storage/hamming_secded), [`raid5_parity`](appD_storage/raid5_parity) | ECC DIMM code; RAID-5 rebuild |
| [App F Interconnect](appF_interconnect) | [`rr_crossbar`](appF_interconnect/rr_crossbar) | crossbar with round-robin arbitration |
| [App H VLIW](appH_vliw) | [`vliw4`](appH_vliw/vliw4) | 4-slot VLIW, exposed pipeline; same kernel at IPC 1.01 / 1.77 / 1.94 by schedule |
| [App J Arithmetic](appJ_arithmetic) | [`carry_lookahead_adder`](appJ_arithmetic/carry_lookahead_adder), [`booth_multiplier`](appJ_arithmetic/booth_multiplier), [`restoring_divider`](appJ_arithmetic/restoring_divider) | adder, multiplier, divider |

Not yet written (prefetching, SIMD, mesh routing, ...):
see the [roadmap](docs/roadmap.md). Chapter 6 (warehouse-scale computers) is a modelling chapter with no RTL.

## Organization

Examples are organized by **topic**, not by edition, because most subjects (pipelines, caches, predictors) recur
in every edition. [`docs/editions.md`](docs/editions.md) compares the seven editions and maps each topic to the
editions that cover it and the ISA each used (DLX, MIPS64, RISC-V).

```
chNN_topic/ | appX_topic/
    README.md                 chapter introduction + example index
    example_name/
        README.md             the textbook-style write-up
        deps.txt              (optional) other examples whose RTL this one reuses
        sv/   *.sv  tb_*.sv   RTL + one self-checking testbench
        vhdl/ *.vhd tb_*.vhd  the same design and the same test in VHDL
scripts/run_tests.py          discovers examples, runs both languages
docs/                         edition guide, roadmap
```

Every testbench prints `TEST PASSED` or `TEST FAILED` and the runner checks the exit code too. The SystemVerilog
and VHDL versions of a test use the same stimulus and expectations (random streams use the same LCG), and
where the design is deterministic they finish at the same simulated time, which is a handy cross-language check.

## Adding an example

1. Create `chNN_topic/new_example/{sv,vhdl}/` with RTL and a `tb_<name>` testbench in each language.
2. The testbench must be self-checking, print `TEST PASSED` on success, and end the simulation itself.
3. Write `README.md` in the same shape as the existing ones; list it in the chapter README, in
   [`docs/editions.md`](docs/editions.md) and in [`docs/roadmap.md`](docs/roadmap.md).
4. `make test T=new_example` must pass in both languages. See [`CLAUDE.md`](CLAUDE.md) for tool quirks.
