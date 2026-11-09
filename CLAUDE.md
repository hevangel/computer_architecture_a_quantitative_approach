# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

The worked examples of Hennessy & Patterson, *Computer Architecture: A Quantitative Approach* (1st-7th editions),
implemented as hardware in **both SystemVerilog and VHDL**, each with a self-checking testbench and a textbook-style
`README.md`. `README.md` has the example index; `docs/editions.md` (edition comparison + topic-to-edition map) and
`docs/roadmap.md` (done vs. planned) are the planning documents -- keep them truthful when you add or change examples.

## Commands

Toolchain: `iverilog` 12 (SystemVerilog, `-g2012`), `ghdl` 4.x mcode (VHDL, `--std=08`), `verilator` 5 (lint only),
Python 3 (stdlib only). Install with `apt-get install iverilog ghdl verilator`.

```bash
make test                          # all examples, both languages (expect "66/66 passed" -- update if you add examples)
make test T=set_assoc_cache        # one example: T is a substring filter on the path (several words allowed)
make test-sv T=ch03                # one language, one chapter  (also: make test-vhdl)
make list                          # show discovered examples
make lint                          # advisory Verilator lint of SystemVerilog (not a gate; many width rules muted)
python3 scripts/run_tests.py -v --lang sv rv32i   # -v prints the exact tool commands and full simulator output
```

Build products go to `build/<example path>/{sv,vhdl}/` (git-ignored). To debug by hand, copy the command lines that
`-v` prints.

## Architecture of the repo

* **Discovery rule:** any directory containing `sv/` or `vhdl/` is an example. `scripts/run_tests.py` is the only
  runner; the `Makefile` just wraps it.
* **Per language, one testbench per example:** exactly one file named `tb_*.sv` / `tb_*.vhd`; its basename is the
  simulation top (`tb_foo.sv` -> module `tb_foo`, `tb_foo.vhd` -> entity `tb_foo`). All other files in the folder are RTL.
* **Compile order:** `deps.txt` (optional, one repo-relative example path per line, `#` comments) pulls in another
  example's RTL first; within a folder `*_pkg.sv` files sort before the rest. VHDL files are imported with `ghdl -i` and built with `ghdl -m`, which analyses them in dependency order
  (plain `ghdl -a` in alphabetical order fails when an entity is instantiated by a file that sorts earlier).
  Several modules per file is fine (e.g. `hamming_secded.sv` holds `secded_encoder` and `secded_decoder`).
* **Pass protocol:** the simulator must exit 0, print `TEST PASSED` and never `TEST FAILED`. SV testbenches end with
  `$finish`; VHDL testbenches `use std.env.all` and call `finish`, reporting with `report "TEST PASSED"` /
  `severity error`.
* **The SV and VHDL halves are the same design and the same test.** When you change behavior or expectations in one,
  change the other. Expected values must come from outside the RTL (hand derivation, an independent Python model, or
  the simulator's own arithmetic operators) -- never copy the RTL's output into the test. Random stimulus uses the
  LCG `x = x*1664525 + 1013904223 (mod 2^32)` in both languages; deterministic designs end at the same simulated time
  in both, which is a useful cross-check.
* **Directory naming** is by topic, using 6th/7th-edition numbering for main chapters (`ch01`-`ch07`) and 5th-edition
  letters for appendices (`appC_pipelining`, `appJ_arithmetic`, ...). Edition differences are documented, not encoded in
  directory names. ISA-specific examples are named by ISA: `rv32i_pipeline5` (6th/7th) and `mips_pipeline5` (one core, `XLEN=32` = DLX/MIPS32
  flavor for the 1st-2nd editions, `XLEN=64` = MIPS64 for the 3rd-5th). Other ISA-dependent examples still lack DLX/MIPS64 variants.
* **Network-style testbenches:** VHDL cannot call procedures of another entity, so a reusable harness is an entity with one process that owns all state and runs a
  scenario chosen by a generic (`mesh_router`); the SystemVerilog harness exposes tasks that the top calls hierarchically. Draw random numbers into variables first
  (argument evaluation order is not specified) so both languages see the same stream.
* **Multi-configuration testbenches:** when one design serves several configurations (e.g. `mips_pipeline5`), the testbench file
  holds a harness module/entity with the generic plus a top `tb_*` that instantiates it once per configuration.
* **New example checklist:** `sv/` + `vhdl/` with testbenches, `README.md` (background / design / verification /
  run it / exercises -- see any existing one), a row in the chapter `README.md`, `docs/editions.md` and
  `docs/roadmap.md`, and the pass count above. Never describe something in a README, the roadmap table of "done"
  items, or CI that is not in the tree and passing.

## Toolchain pitfalls (each one cost real debugging time)

Icarus Verilog (`-g2012` is a subset of SystemVerilog):
* No `break`/`continue` ("sorry: break statements not supported") -- use a `done` flag and `while`.
* Functions cannot contain delays or event controls -- use tasks with `output` arguments.
* **Narrow signed unpacked-array elements are mis-extended when multiplied in a wider context**, even with `$signed()`.
  Copy each operand into a full-width `logic signed` temporary first, then multiply (see `systolic_array.sv`). Do the
  same in testbench golden models.
* A ternary result cannot be assigned to an enum-typed variable without a cast; use `if`/`case`.
* `always_comb` blocks that index arrays print `sorry: constant selects in always_* processes ...` -- benign.
* A function that needs `#delay` cannot be a function: make it a task with an `output` and call it as a statement (it cannot sit inside an expression).
* `int x = 0;` initializers on declarations inside tasks/blocks need `automatic` or a separate assignment.
* Array literals (`a = '{1, 2, 3};`) cannot be assigned ("Assignment to an entire array ... not yet supported"); assign element by element.
* Part-selecting a function call (`f(x)[15:0]`) is a syntax error; assign to a variable first.
* `vvp` can die with `Assertion 'value' failed` (event.cc) on `always_comb` blocks that index unpacked arrays with `int`-typed array
  elements; use fixed-width `logic` vectors for indices/counters held in arrays (see `tomasulo_rob.sv`).

GHDL / VHDL-2008:
* VHDL is **case-insensitive**: a loop variable `n` or `m` collides with a generic or constant `N` / `M`, and a local
  `s` hides a constant `S` (silently turning `s = S` into a tautology -- watch for `-Whide` warnings). Name generics
  distinctly from loop variables (`DIM`, `ROWS`, `lane`).
* Helper functions that read signals must be declared `impure function` -- **but an impure function's internal signal reads are NOT
  in a `process(all)` sensitivity list.** Calling one from a combinational process silently misses updates (this made a MIPS64-only
  failure in `mips_pipeline.vhd`). In combinational processes pass every signal as an argument to a *pure* function; impure is fine
  in clocked processes and testbenches.
* Context clauses (`use ieee.numeric_std.all;`) belong to ONE design unit: a second entity in the same file needs its own `library`/`use` lines. Identifiers cannot end in `_`.
* `sll`, `srl`, `rol`, `and`, `xor`... are reserved words: an assembler function named `sll` will not parse (use `shl`).
* GHDL stops the run at the first `report ... severity error`, so with several failures you only see the first one; after fixing it,
  later checks (e.g. cycle counters) may still fail. Don't assume the unseen checks pass.
* A `process(all)` that runs at time 0 can see undriven `U` values from another process; guard array indexing with `is_x(...)`.
* Integer literals above 2^31-1 (`16#A5A50000#`) overflow; use bit-string literals (`x"A5A50000"`).
* Dividing/multiplying `numeric_std` values widens the result; `resize` it back explicitly.
* A user-defined 64-bit integer type with extreme bounds (`range -(2**62) to 2**62`) crashed GHDL 4.1 mcode ("GHDL Bug occurred ... overflow check failed"); bounds like `2**56` are fine. VHDL `integer` is only 32 bits, so 64-bit golden models need such a type (or `signed`/`unsigned`).

Verilator is used for lint only; `scripts/run_tests.py` mutes the width/style rules deliberately (the examples favor
readability and Icarus compatibility over lint-cleanliness).
