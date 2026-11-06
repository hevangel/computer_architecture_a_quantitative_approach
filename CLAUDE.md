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
make test                          # all examples, both languages (expect "26/26 passed" -- update if you add examples)
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
  example's RTL first; within a folder `*_pkg.sv` files sort before the rest (GHDL resolves VHDL order itself).
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
  directory names. ISA-specific examples are named by ISA (`rv32i_pipeline5`; DLX/MIPS64 variants are planned for the
  1st-5th editions).
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
* `int x = 0;` initializers on declarations inside tasks/blocks need `automatic` or a separate assignment.

GHDL / VHDL-2008:
* VHDL is **case-insensitive**: a loop variable `n` or `m` collides with a generic or constant `N` / `M`, and a local
  `s` hides a constant `S` (silently turning `s = S` into a tautology -- watch for `-Whide` warnings). Name generics
  distinctly from loop variables (`DIM`, `ROWS`, `lane`).
* Helper functions that read signals must be declared `impure function`.
* Integer literals above 2^31-1 (`16#A5A50000#`) overflow; use bit-string literals (`x"A5A50000"`).
* Dividing/multiplying `numeric_std` values widens the result; `resize` it back explicitly.

Verilator is used for lint only; `scripts/run_tests.py` mutes the width/style rules deliberately (the examples favor
readability and Icarus compatibility over lint-cleanliness).
