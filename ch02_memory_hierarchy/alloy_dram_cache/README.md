# Direct-mapped DRAM cache with miss prediction

This read-only teaching model pairs a four-line direct-mapped tag-and-data
cache with a four-entry, two-bit hit/miss predictor. It serves one outstanding
request at a time. The tag and data are modeled as parts of the same cache
access; a correct predicted miss starts a backing read after the predictor
delay, in parallel with tag lookup. A miss predicted as a hit waits until the
tag result before starting that read. A predicted miss that is actually a hit
returns the cache data and counts the unnecessary backing read.

The default delays are 30 cycles for the tag, four additional cycles for hit
data, 100 cycles for backing memory, and one cycle for prediction. Thus a hit
takes 34 cycles, a serial miss 130, and a correctly predicted miss 101. The
backing store is a deterministic function of the line address. The predictor
is a simple indexed saturating-counter design inspired by miss prediction; it
is **not a verified implementation of MAP-I**. The model omits writes, queues,
DRAM row timing, data-transfer contention, cancellation cost and overlapping
requests, so it does not model real-cache throughput or energy.

Both testbenches run two 20-access profiles, measuring actual response cycles
and counting prediction outcomes and backing reads:

| Profile | Correct hit / correct miss / false hit / false miss | Serial average | Predicted average | Serial / predicted backing reads |
|---|---|---:|---:|---:|
| 7th-edition exercise profile | 16 / 1 / 1 / 2 | 43.6 | 42.15 | 2 / 4 |
| Review's 80% hits / 15% correct misses / 5% false hits | 15 / 3 / 1 / 1 | 53.2 | 48.85 | 4 / 5 |

For example, the first predicted average is `(18×34 + 1×101 + 1×130)/20`.
False misses are included among hits in the second profile. These figures use
the specified synthetic timing and are not measured hardware performance.

The targeted SystemVerilog and VHDL tests passed with Icarus Verilog 14.0
development and GHDL 6.0.0, finishing at 19,790 ns. Verilator 5.055 lint passed
with the repository's warning settings. Run from the repository root:

```sh
python scripts/run_tests.py -v alloy_dram_cache
```

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 2, section 2.3 and exercise 2.29. The
implementation and test traces are original.
