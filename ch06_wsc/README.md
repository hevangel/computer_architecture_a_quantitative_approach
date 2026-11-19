# Chapter 6 -- Warehouse-Scale Computers

Cloud services run on warehouses of commodity servers. The chapter is about *system-level* metrics rather than
logic: **cost** (capital and operating, dominated by servers, power and cooling), **PUE** (total facility power
divided by IT power), **tail latency**, availability through software redundancy, and the power/performance of
server-class workloads. Introduced as a chapter in the 5th edition.

## Examples

The [Clos/OCS fabric](clos_ocs_fabric/README.md) compares fixed and reconfigured packet paths across eight leaves and four spines.

## Analytical models

The [Python model suite](python/wsc_model_suite.py) explores PUE, energy cost, undiscounted ownership cost,
operational and allocated embodied carbon, serial transfer time, and fan-out latency with delayed hedging.
The hierarchy model aggregates independent server capacity and combines storage and network
latencies with the slowest link bandwidth. It estimates request time for a specified distribution
of local, rack and array accesses. A linear idle-to-peak server power model and an annualized fleet cost model account for
server and facility amortization, provisioned IT capacity, utilization periods and energy.
It also simulates primary, hedged and tied requests through two FIFO servers, including queue contention,
immediate cancellation and consumed server time. Both models use caller-supplied service durations and omit
network and cancellation delays and failures; the analytical fan-out calculation also omits contention.
The hierarchy model assumes pipelined transfer at the bottleneck bandwidth, additive fixed
latencies, no contention or protocol overhead, and no replication. Its tests reproduce the
6th edition, §6.3, pp. 480–481 transfer comparison: a 1,000 MB transfer takes 0.05 s
locally from DRAM versus 5 s from disk; the network limits either medium to 10 s within
the rack and 100 s across the array. For 90% local, 9% rack and 1% array accesses,
the stated 0.1, 100 and 500 microsecond latencies yield 14.09 microseconds; the
extracted textbook example contains inconsistent arithmetic, so the test uses the stated inputs.

The fleet cost model assumes powered-on identical servers, a constant PUE, 8,760 hours per year,
and straight-line amortization; it excludes financing, replacement timing, and discounting.
Facility cost is specified per watt of provisioned IT capacity, and other operating costs must
exclude energy. For example, 100 servers at 100 W idle and 300 W peak draw 20 kW at 50% utilization.
With 4,380 hours each at 10 and 30 kW, PUE 1.2, and electricity at $0.10/kWh,
annual facility energy costs $21,024. Adding $100,000 server amortization, $30,000 facility
amortization and $5,000 other costs yields $156,024 per year. These are synthetic inputs,
not a textbook case study. The financed monthly model also covers the Hamilton case in 6th edition §6.4, Figures 6.13–6.14, and 7th edition §6.4, Figure 6.32. It uses the displayed 8 MW critical IT load, 80% average utilization, 1.45 PUE, $0.07/kWh and a 730-hour month, plus the published rounded capital costs, 5% nominal interest and amortization periods. It calculates 9.28 MW facility power, $474,208 monthly electricity and about $3.787 million total per month including $85,000 in people costs. The book reports approximately $475,000 and $3.8 million; its $290,000 networking row differs from the approximately $295,005 level payment computed from the displayed rounded inputs. This Hamilton scenario is not presented as the cost of a particular Google facility.

`four_m_carbon` separates the operational effects of Model, Machine, Mechanization (PUE) and Map (grid intensity), then adds caller-allocated embodied emissions. The 7th edition, Chapter 7 §7.8, reports approximately 65× and 747× operational-emissions reductions in its 2019 and 2021 comparisons. Using its rounded combined Model/Machine, PUE and grid factors reproduces those orders of magnitude; the numbers are not independent measurements and do not establish an embodied-carbon reduction. The model assumes equivalent work and caller-supplied energy ratios. Multi-tier queueing remains planned. The Python suite is separate from the HDL tests. Run it with:

```sh
python -m unittest discover -s ch06_wsc/python -p 'test_*.py'
```

For background, see Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 7th edition
(2025), Chapter 6, sections 6.1–6.7. Inputs in the tests are synthetic, not measurements of a real facility.
The hardware building blocks WSCs rely on appear elsewhere in this repository:
[`appF_interconnect`](../appF_interconnect) (switches), [`appD_storage`](../appD_storage) (ECC, RAID).
