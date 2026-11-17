# Chapter 6 -- Warehouse-Scale Computers

Cloud services run on warehouses of commodity servers. The chapter is about *system-level* metrics rather than
logic: **cost** (capital and operating, dominated by servers, power and cooling), **PUE** (total facility power
divided by IT power), **tail latency**, availability through software redundancy, and the power/performance of
server-class workloads. Introduced as a chapter in the 5th edition.

## Status

The [Python model suite](python/wsc_model_suite.py) explores PUE, energy cost, undiscounted ownership cost,
operational and allocated embodied carbon, serial transfer time, and fan-out latency with delayed hedging.
It also simulates primary, hedged and tied requests through two FIFO servers, including queue contention,
immediate cancellation and consumed server time. Both models use caller-supplied service durations and omit
network and cancellation delays and failures; the analytical fan-out calculation also omits contention.
A complete 4M sustainability analysis and multi-tier queueing remain planned. It is separate from the HDL test suite. Run it with:

```sh
python -m unittest discover -s ch06_wsc/python -p 'test_*.py'
```

For background, see Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 7th edition
(2025), Chapter 6, sections 6.1–6.7. Inputs in the tests are synthetic, not measurements of a real facility.
The hardware building blocks WSCs rely on appear elsewhere in this repository:
[`appF_interconnect`](../appF_interconnect) (switches), [`appD_storage`](../appD_storage) (ECC, RAID).
