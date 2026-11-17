# Prime+Probe and way partitioning

This single-set, four-way tag-only cache illustrates interference between a
victim (`domain_id=0`) and a spy (`domain_id=1`). On each accepted request it
returns a hit after one cycle or a miss after five cycles, with FIFO replacement.
The latency constants are configurable positive cycle counts. A request is
accepted only when `req_ready` is high; `response_valid` marks completion.
Hits and misses observed by the spy are counted separately.

With partitioning disabled, both domains compete for all four ways. With it
enabled, the victim uses ways 0–1 and the spy uses ways 2–3, including separate
replacement pointers. The partition setting is sampled on reset, which also
invalidates every line. The design does not support changing partitions live.

The matched self-checking testbenches exercise a no-victim control and a
secret-dependent victim access. In the shared case the victim evicts the
oldest of four spy lines, so probing that line changes from a one-cycle hit to
a five-cycle miss. In the partitioned case, both primed spy lines remain hits
even after five distinct victim misses. Both language tests pass at 1,270 ns:

```sh
python scripts/run_tests.py -v prime_probe_qos
```

Icarus Verilog 14.0 development and GHDL 6.0.0 passed the targeted tests;
Verilator 5.055 lint passed with the repository's warning settings. This is a
controlled teaching model: it has no data values, multiple sets, coherence,
concurrent requests, shared-bandwidth contention or operating-system effects.
Partitioning eliminates the illustrated replacement channel only; it is not a
proof that a real system has no side channels.

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 2, section 2.4. The RTL and traces are
independently authored.
