# Tagged geometric-history branch predictor

**Topic:** dynamic branch prediction · **Reference:** Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Chapter 3 §3.3, Figure 3.7 and accompanying discussion (PDF pp. 220–221). This is an original small teaching implementation, not a commercial predictor.

A 16-entry, two-bit bimodal base is combined with three 16-entry tagged tables using global-history lengths 2, 6 and 18. Each tagged entry has a valid bit, eight-bit partial tag, three-bit saturating prediction counter and two-bit usefulness counter. The longest matching history supplies the prediction; the next matching table or base is the alternate. The base is trained on every resolved branch. When provider and alternate disagree, usefulness moves toward the provider's correctness. On a misprediction, the first eligible longer-history entry that is invalid or has zero usefulness is allocated; if none is available, eligible usefulness counters are decremented.

The byte-addressed 16-bit `pc` and current history form each index and folded tag. `prediction`, `provider` (0 for base, 1–3 for tagged tables) and the separate four-bit-history `gshare_prediction` are combinational. An asserted `update_valid` at a rising edge trains the same PC with `actual_taken` and shifts global history. Query and resolution must therefore refer to the same branch: there is no speculative history, in-flight metadata, target prediction or branch recovery. Reset clears history and valid bits and initializes counters weakly not taken. The small tables, simple allocation and absence of periodic usefulness aging are deliberate simplifications; the TAGE and gshare models use different amounts of storage.

The independent Python reference generates 7,024 deterministic predictions, including a repeating 16-outcome pattern followed by varied PCs and outcomes. Both HDL testbenches compare prediction, gshare prediction and provider on every update, and verify disabled updates hold state. The pattern contains a repeated six-bit context with different successors. After 4,000 warm-up branches, the next 2,000 contain zero TAGE errors versus 125 four-bit gshare errors; the longest-history table supplies 250 predictions in that interval. This is a constructed example, not a general performance guarantee. Reference unit tests also check saturation, longest-match selection and usefulness protection.

```sh
python ch03_ilp/tage_predictor/python/generate_vectors.py --check
python -m unittest discover -s ch03_ilp/tage_predictor/python -p 'test_*.py'
python scripts/run_tests.py tage_predictor
```
