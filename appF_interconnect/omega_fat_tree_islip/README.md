# Omega Network and iSLIP Arbitration

**Reference** — Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Appendix F §§F.4 and F.6. The Omega forwarding fabric and the iSLIP crossbar scheduler are separate models.

## Omega network

Three stages each contain four 2×2 switches. Stages use destination bits from most to least significant. A perfect shuffle rotates the three-bit output index between stages. Each input has a one-flit buffer, whose empty state supplies one downstream credit. An output reserves one input from the first flit through its accepted tail. Round robin chooses between new contenders. Each packet presents the same destination on all of its flits.

The testbench injects eight three-flit packets with periodic egress stalls. It checks each flit's destination, order and tail, and verifies that stalled outputs retain the selected data. In the conflict-free permutation every packet has a different wire in each stage. Bit reversal uses all eight outputs but shares wires in the middle stage. The same 24 flits drain in 8 and 15 cycles respectively.

## iSLIP arbiter

Each iteration grants free outputs to requesting free inputs using per-output round robin. Each input accepts at most one of its grants using a separate round-robin pointer. Matched inputs and outputs leave the current allocation. Only first-iteration accepts update the persistent pointers, and only on an edge with `advance` asserted.

The tests compare four rounds with one round on the same request snapshots. A directed case tests additional-round matching and pointer update rules. Over 32 repeated snapshots, four iterations accept 86 slots versus 76 in the one-iteration baseline. This measures arbitration utilization for the supplied matrices. The allocator is combinational and the example establishes no clock frequency or universal throughput gain.

```sh
python scripts/run_tests.py -v omega_fat_tree_islip
```

## Exercises

1. Enumerate permutations and compare actual contention with shared-wire counts predicted from the shuffle.
2. Add multiple virtual channels and compare their effect on blocked output reservations.
