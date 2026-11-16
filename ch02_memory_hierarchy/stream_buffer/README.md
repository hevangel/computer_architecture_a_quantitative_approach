# Direct-mapped cache with a stream buffer

This example places a four-entry FIFO stream buffer alongside an eight-line,
direct-mapped, read-only L1. A request is a 32-bit **line address**; each line
contains one 32-bit word. A cache miss probes the FIFO head. A head hit supplies
the L1 and appends the next sequential line; any other miss fetches the demand
line and replaces the FIFO with the four following lines. Prefetches never enter
L1 until demanded. Disabling prefetching invalidates the FIFO. Address arithmetic
wraps at 32 bits.

The backing store is the deterministic function `line_address XOR 0xa5c39e71`,
and all reads and FIFO fills are idealized to complete during the request cycle.
This permits a one-request-per-cycle functional comparison but **does not model**
memory latency, limited bandwidth, outstanding requests, cache writes, or
prefetch timeliness. Counters distinguish L1 hits/misses, demand reads,
prefetch hits and prefetch reads. The last category counts every issued fill,
including lines discarded on a stream replacement, so demand reduction is not
the same as lower total traffic.

Both self-checking testbenches use identical traces and finish at 670 ns:

| Trace | Buffer | Demand reads | Prefetch hits | Prefetch reads |
|---|---:|---:|---:|---:|
| 32 sequential lines | off | 32 | 0 | 0 |
| 32 sequential lines | on | 1 | 31 | 35 |
| Two alternating 16-line streams | off | 32 | 0 | 0 |
| Two alternating 16-line streams | on | 32 | 0 | 128 |

The sequential case reduces demand reads by 96.875%, while increasing total
backing reads from 32 to 36 under this eager-fill model. The interleaved case
exposes the single-stream limitation and discarded prefetch traffic. A repeat
access checks the L1-hit path; both testbenches compare returned data to the
independent backing-store function. To rerun from the repository root:

```sh
python scripts/run_tests.py -v stream_buffer
```

The targeted run passed with Icarus Verilog 14.0 development and GHDL 6.0.0;
Verilator 5.055 lint passed using the repository's warning settings. For
background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 2, section 2.3 (prefetching). The
implementation and test traces are original.
