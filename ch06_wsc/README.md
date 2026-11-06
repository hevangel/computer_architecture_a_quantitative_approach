# Chapter 6 -- Warehouse-Scale Computers

Cloud services run on warehouses of commodity servers. The chapter is about *system-level* metrics rather than
logic: **cost** (capital and operating, dominated by servers, power and cooling), **PUE** (total facility power
divided by IT power), **tail latency**, availability through software redundancy, and the power/performance of
server-class workloads. Introduced as a chapter in the 5th edition.

## Status

There is **no RTL in this chapter** because the material is quantitative modelling of systems far larger than any
block you can simulate. A planned companion is a small Python/queueing model of tail latency and PUE (outside the
HDL test suite). The hardware building blocks WSCs rely on appear elsewhere in this repository:
[`appF_interconnect`](../appF_interconnect) (switches), [`appD_storage`](../appD_storage) (ECC, RAID).
