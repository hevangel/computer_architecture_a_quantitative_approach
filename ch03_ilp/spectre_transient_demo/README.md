# Transient bounds check and cache footprint

**Topic:** speculative execution and microarchitectural state · **Reference:** Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 7th edition (2025), Chapter 3 §3.13; see also the Spectre discussion in Chapter 1. This is an original abstract teaching model, not a model of a particular processor or a working exploit.

The model predicts that an index is in bounds while a branch takes `BRANCH_LATENCY` cycles to resolve. A speculative read selects an 8-bit value from a 256-byte secret array, then touches one of 256 abstract cache lines indexed by that value. A probe reports one cycle for a marked line and ten cycles for an unmarked line. If the check fails, the architectural result is not changed, but a line touched before resolution remains marked. The mitigation blocks the dependent read until the check resolves. A legal access then executes and commits normally; an illegal one performs no protected read or touch.

`host_we`, `host_addr`, and `host_data` initialize secret bytes while idle. `flush` clears cache marks while idle; `start` latches the index, bound and mitigation choice. `busy` and the one-cycle `done` pulse delimit the operation. `arch_value` retains the last committed legal value. `transient_load` and `transient_touch` identify work issued before branch resolution; `probe_index` selects the line observed by `probe_cycles`. The 9-bit bound permits the range 0–256. Reset clears the cache and architectural result but does not initialize secret memory. Initialize every location that will be read, and use host writes and flush only while idle.

Both testbenches execute legal and illegal accesses with mitigation off and on, check architectural equivalence, and probe every line. With the default five-cycle branch window, an unprotected illegal access leaves exactly the secret-selected line marked; the protected run leaves all lines unmarked. A one-cycle branch window resolves before the dependent touch and leaves no wrong-path footprint. A mutation that bypasses the mitigation fails the protected wrong-path assertion. These are abstract deterministic timings; there are no real cache sets, replacement, predictor training, instruction retirement, operating-system isolation or host timing measurements. The mitigation models delaying the dependent read, not the guarantees of any particular hardware fence.

```sh
python scripts/run_tests.py spectre_transient_demo
```
