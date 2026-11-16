# Tournament predictor, target buffer and return stack

This non-speculative teaching predictor compares a local-history predictor with
a global-history predictor. Four PC-indexed two-bit local histories select one
of four local two-bit counters per PC index; a two-bit global history selects
one of four shared global counters. Four PC-indexed two-bit selector counters
choose between them and train only when the components disagree. All counters
start weakly not-taken or weakly favoring local. The PC index is `pc[3:2]`, so
different branches can alias. Query and resolution share one PC input: supply a
stable resolving PC and its actual result when asserting `update_valid`.
Updates are non-speculative; multiple unresolved branches, rollback and
simultaneous unrelated query/update are outside this model.

A four-entry direct-mapped BTB uses the full PC as tag. Taken branch and call
updates install their actual target; not-taken branches leave it unchanged. A
four-entry return-address stack pushes `pc+4` on a call and pops on a return.
An empty pop has no effect; pushing a fifth address discards the oldest entry.
The interface assumes fixed four-byte instruction spacing and does not model
compressed instructions or delayed branches.

Both testbenches check identical synthetic traces after warm-up:

| Trace | Samples | Local correct | Global correct | Tournament correct |
|---|---:|---:|---:|---:|
| Four periodic branches | 1,920 | 1,920 | 1,440 | 1,920 |
| Two correlated branches | 3,840 | 1,994 | 2,724 | 2,736 |

These numbers describe the selected traces, not a general predictor ranking.
Tests also check a BTB hit, conflict replacement and tag mismatch, all four
nested return predictions, stack underflow, and the overflow policy. The
[Python reference](test_reference.py) independently computes trace counts.
Icarus Verilog 14.0 development and GHDL 6.0.0 passed the targeted tests with
both testbenches finishing at 61,671 ns; Verilator 5.055 lint passed with the
repository's warning settings. From the repository root:

```sh
python scripts/run_tests.py -v tournament_btb_ras
python -m unittest discover -s ch03_ilp/tournament_btb_ras -p 'test_*.py' -v
```

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 3, sections 3.3 and 3.9. The model,
traces and explanations are independently authored.
