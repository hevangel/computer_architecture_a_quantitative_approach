# CPI and switching-activity counters

The SystemVerilog and VHDL versions count elapsed cycles, retired instructions,
stalls and four classes of each. Class indices 0–3 can represent ALU, load,
store and branch, or structural, data, control and cache-miss stalls. The
caller supplies these classifications; the block does not decode instructions.
Retirement and stall inputs are independent, so the caller must make them
mutually exclusive and cover every cycle to interpret cycles as busy plus stalls.
The `cpi_q16` output is floor(`cycles * 2^16 / retired`), or zero when there
are no retirements. Counter overflow wraps at 32 bits.

On each enabled cycle the block counts changed bits from the last enabled
sample of a 32-bit activity bus. While disabled the remembered sample is held.
Parameters give Q16.16 energy per bit transition and static energy per cycle;
the 64-bit dynamic and static accumulators wrap on overflow. The most recent
cycle's energy multiplied by `CLOCK_HZ` is `last_power_q16`. For physical units,
choose joules per transition as `0.5 * C * V²`, static joules per cycle as
`I_static * V / frequency`, and frequency in Hz. The model uses a uniform
capacitance per bit and assumes these parameters remain fixed; it is a switching
proxy, not a measured chip power estimate.

Both testbenches specify the same 10-cycle baseline and reduced-stall/gated
trace. An independent [Python trace calculation](test_trace_model.py) checks the
expected CPI, per-class counts, energy and 40% reduction in dynamic energy:

```sh
python -m unittest discover -s ch01_fundamentals/cpi_power_counters -p 'test_*.py' -v
python scripts/run_tests.py -v cpi_power_counters
```

**Verification status:** the trace calculation passes, and the targeted runner
passed both testbenches with Icarus Verilog 14.0 development and GHDL 6.0.0.
Both produced the expected counts and finished at 110 ns.

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 1, sections 1.5 and 1.8–1.9. The design,
test vectors and explanations are original.
