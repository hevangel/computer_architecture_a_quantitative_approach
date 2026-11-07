# DRAM Controller: Row Buffers, FR-FCFS Scheduling and Refresh

**Topic:** Chapter 2 (Memory Technology and Optimizations) / Appendix B · **Editions:** 2-7 (DRAM organisation grew from a few paragraphs to a full section) ·
**Files:** [`sv/dram_ctrl.sv`](sv/dram_ctrl.sv), [`sv/dram_device.sv`](sv/dram_device.sv), [`vhdl/dram_ctrl.vhd`](vhdl/dram_ctrl.vhd), [`vhdl/dram_device.vhd`](vhdl/dram_device.vhd)

## Background

A DRAM chip is a set of **banks**; each bank is a two-dimensional array of capacitor cells whose rows are read destructively into a **row buffer**
(the sense amplifiers). Reading a word is therefore a three-command protocol:

| Command | Effect | Constraint it creates |
|---------|--------|-----------------------|
| `ACT` (activate) | copy row *r* of a bank into its row buffer | `tRCD` before a column access; `tRAS` before `PRE`; `tRRD` before another `ACT` |
| `RD` / `WR` | access one burst of the open row | `tCL` (`tCWL`) to the data; `tCCD` between column commands; `tWTR`, `tRTW` on bus turn-around |
| `PRE` (precharge) | write the row back and close the bank | `tRP` before the next `ACT`; `tRTP`, `tWR` after the last column access |
| `REF` | refresh every row (all banks idle) | `tRFC` before the next `ACT`; one every `tREFI` |

So the latency of a request depends on the **state of the row buffer**: a **row hit** needs only the column access; a **row miss** (bank closed) adds an
activate; a **row conflict** (another row open) adds a precharge and an activate. The memory controller's job
is to turn a stream of requests into a legal command stream that keeps the narrow data bus busy: it **reorders** requests to harvest row hits and to
overlap the activates of one bank with the bursts of another, it chooses an **open-page** or **closed-page** policy, and it inserts **refresh**.

## Design

The device ([`dram_device`](sv/dram_device.sv)) has 4 banks x 16 rows x 4 bursts; a burst is 128 bits (BL = 4 beats). It stores data *and* contains an
**independent timing checker**: it keeps a timestamp of every command and raises a sticky `violation` for any broken constraint or protocol error (`RD` to a
closed bank, `REF` with a bank open, ...). It also records the longest interval between refreshes. Default timing (cycles): tRCD 3, tCL 3, tCWL 2, tRP 3,
tRAS 7, tWR 3, tRTP 2, tRRD 2, tCCD 4, tWTR 3, tRTW 6, tRFC 12.

The controller ([`dram_ctrl`](sv/dram_ctrl.sv)) accepts one burst request per cycle into an 8-entry queue (`req_ready` goes low when full) and issues **at most
one command per cycle**:

* Per bank it keeps the open row and **down-counters** for the constraints (`tRCD`, `tRAS`/`tRTP`/`tWR`, `tRP`/`tRFC`); globally for `tRRD`, `tCCD`, `tWTR`, `tRTW`.
* **Hazard rule:** a request is not eligible while an older request to the *same burst address* is queued, so reordering never changes program-order data.
* **FR-FCFS** (`FR_FCFS = 1`): among eligible requests, a ready *column* command (row hit) wins over `ACT`/`PRE`, oldest first within each class; a row is not
  closed while any queued request still hits it. **FCFS** (`FR_FCFS = 0`): only the oldest request may make progress.
* **Open page** (`OPEN_PAGE = 1`): leave the row open until a conflict or refresh. **Closed page**: precharge as soon as no queued request hits the row.
* **Refresh:** every `tREFI` cycles the controller stops starting new work, precharges the open banks, issues `REF`, and resumes after `tRFC`.
* Reads answer on `rd_resp_*` when the data arrives from the device; writes answer on `wr_resp_*` when the burst has been transferred.

The request path costs 2 cycles (queue write, command decision plus registered output), which gives the latency formulas the testbench checks:

```
row hit      q + 2 +             tCL + BL  =  9
row miss     q + 2 +       tRCD + tCL + BL  = 12
row conflict q + 2 + tRP + tRCD + tCL + BL  = 15
```

## Verification

Expected numbers are derived by hand from the timing parameters (never copied from the RTL), and every run also demands that each read returns the
program-order value (a shadow memory in the testbench), that no request is lost, and that the device's checker reports **zero violations**.

| Test | Expectation | Result |
|------|-------------|--------|
| Idle latencies, open page / FCFS | miss 12, hit 9, conflict 15 | pass |
| Idle latencies, closed page | 12 / 12 / 12 (bank already precharged) | pass |
| `A0 B0 A1 B1 A2 B2 A3 B3`, A and B two rows of one bank | FR-FCFS 2 activations, FCFS 8; FR-FCFS faster (44 vs ~82-86 cycles) | pass |
| 300-request random streams x 3 (hot set with many same-address hazards, wide random, 80 % row locality) x 3 policies | data correct, no violations; FR-FCFS total time <= FCFS on the row-locality stream | pass |
| 64 sequential bursts (4 banks x 4 rows) | finish exactly `q + 264` cycles = `2 + tRCD` + 63 x tCCD + tCL + BL: 96 % of peak bandwidth, 16 `ACT`, 64 `RD` | pass |
| `tREFI = 100`, 720-cycle window under traffic | 5-8 `REF` commands, controller's count equals device's, longest gap <= 140 | pass (6-7) |

Mutation spot checks: removing the same-address hazard, or shortening `tRCD` by one cycle in the controller, makes the testbench fail in both languages.
The deterministic numbers (latencies, activations, 264 cycles) are identical in SystemVerilog and VHDL; the random-stream averages differ slightly because each
VHDL harness starts at reset while the SystemVerilog ones run one after another, so the refresh phase differs.

## Run it

```bash
make test T=dram_controller
python3 scripts/run_tests.py -v dram_controller    # prints the latency / activation / bandwidth summary
```

## Exercises

1. Make the closed-page policy adaptive (keep a row open while the queue holds a hit, as here, but also for a few cycles after the last hit) and find the
   stream where it beats both pure policies.
2. Add **write batching**: hold writes until a high-water mark, then drain them, to amortise `tWTR`/`tRTW` turn-around. How does read latency change?
3. Change the address map from `row|bank|col` to `row|col|bank` (bank-interleaved bursts). Which of the test streams gains most?
4. Add per-bank refresh (refresh one bank while the others keep working) and measure the throughput recovered at `tREFI = 100`.
5. Replace the oldest-first column rule with an **age cap** so a row-hit stream cannot starve an old conflicting request, and construct the starving stream
   that breaks plain FR-FCFS.
