# West-First Adaptive Mesh with Speculative Allocation

**Reference** — Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Appendix F §§F.5–F.6.

The 4×4 mesh has five input ports per node, including injection, with two single-flit virtual channels per input. Each packet contains an ID and destination. An empty downstream VC supplies credit. Each physical input and output can carry at most one flit per cycle. Router-local arbitration rotates the starting input. A stalled local output retains its selected packet.

Routing takes every required westward step before turning. Otherwise the router compares the free downstream VCs for legal minimal directions, trying east first on ties. A disabled link has no usable credits. In speculative mode switch selection and VC matching share a cycle. A transfer commits only when both match and a credit exists. In serialized mode an output retains an allocation for the next cycle, and a subsequent switch transfer consumes the credit. Both modes leave packet and VC state intact on a blocked transfer.

Both testbenches compare an unloaded westbound hop in the two modes. From the accepted ingress edge to the first valid signal at the next node takes one cycle in speculative mode and two in serialized mode. The hotspot trace injects five packets at each of 16 nodes, disables east at router 0, and stalls the sink periodically. All 80 IDs arrive once at the sink after 240 minimal link hops, including 63 alternative choices, in 107 cycles. The design compares single-flit routes and does not guarantee arrival order across adaptive paths. Multi-flit VC reservations and physical link timing are outside the example.

```sh
python scripts/run_tests.py -v west_first_adaptive_spec_vc
```

## Exercises

1. Add multi-flit packets and preserve each reserved route until its tail.
2. Compare per-destination queue depth and latency under uniform and hotspot traffic.
