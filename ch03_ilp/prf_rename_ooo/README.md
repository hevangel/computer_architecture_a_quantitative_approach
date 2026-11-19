# Physical Register Renaming and Out-of-Order Execution

**Topic:** Physical register files, register maps and precise rollback · **Edition:** 6th edition, Chapter 3 §3.8 · **Files:** [SystemVerilog](sv/prf_rename_ooo.sv), [VHDL](vhdl/prf_rename_ooo.vhd), [Python reference](python/prf_reference.py)

## Background

A physical register file lets successive architectural writes use distinct storage. The front-end map names the latest speculative writer, while the architectural map advances in commit order. A free list supplies new physical registers. Branch recovery must discard younger mappings while preserving older writers, including ones that committed after the branch was issued. These are original teaching models of the cited concepts.

## Design

The hardware has eight architectural registers, an eight-entry pointer-only ROB, and a physical register file with `NPHYS` from 9 to 16 (16 by default). A bitmap allocates the lowest available physical register. ROB entries contain physical source, new-destination and old-destination identifiers; computed values live in the PRF. Issue and commit are each at most one instruction per cycle. One add/subtract/branch unit and one multiply unit select the oldest ready entry independently; a single result bus gives the add unit priority. Results mark physical registers ready, while in-order commit updates the architectural map and frees the old physical destination.

The input accepts `ADD`, `SUB`, `MUL`, or a predicted `BNEZ` condition. A misprediction squashes younger ROB entries, cancels their executing units, rebuilds the front-end map from the current architectural map and surviving ROB, and reconstructs the free bitmap. `recover_valid`, `recover_taken` and the opaque `recover_branch_id` notify the external front end which branch redirected; `issue_ready` remains low during that notification so a held wrong-path request is not accepted. The external front end supplies instructions and is responsible for selecting and refetching the target. There is no memory unit, instruction fetch, exception mechanism or full ISA decoder in this teaching engine.

## Verification

The same HDL tests check correct and incorrect predictions, nested branch recoveries with distinct branch identifiers, older writers that have or have not committed, exact map and free-bitmap restoration, and a request held through recovery. A 12-register configuration exhausts its free list while only four of eight ROB entries are occupied, accepts a branch that needs no destination while the list is empty, then checks allocation after commit and recovery. A 120-instruction WAW/WAR-heavy trace is compared with an independent sequential result and the Python reference; both HDL simulations report 29 out-of-order completions and check free-register conservation on every cycle. Both finish at the same simulated time.

The separate Python reference permits caller-selected legal completion order and checks the PRF partition and map invariants after every operation. It is functional and untimed, while the HDL has fixed execution latencies and arbitration.

## Run it

```sh
python -m unittest discover -s ch03_ilp/prf_rename_ooo/python -v
python scripts/run_tests.py -v prf_rename_ooo
```

## Exercises

1. Add fetch, branch targets and a complete instruction set around the external issue interface.
2. Add memory operations, precise exceptions and variable-latency execution.
3. Replace bitmap selection with a multi-allocation free queue for wider issue and commit.
