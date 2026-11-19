# Clos Fabric with Optical Circuit Reconfiguration

**Reference** — Hennessy, Patterson and Kozyrakis, *Computer Architecture: A Quantitative Approach*, 7th edition (2025), Chapter 6 §6.4. This example isolates the effect of changing which racks share a spine in a small packet fabric.

## Design

Eight leaves each accept packets on four local ingress lanes and connect to two unit-rate uplinks, a 2:1 access-to-uplink ratio. Spine 0 reaches every leaf. Four independent 2×2 crossbars map each leaf pair's two secondary ports onto distinct spines. Pairs 0 and 1 use spines 1 and 2, and pairs 2 and 3 use spines 2 and 3. A crossbar may use straight or crossed mapping. Each rack keeps two links, while the number of common paths for a rack pair can change.

Each ingress lane holds a packet's ID and destination. A rotating scan matches queued packets against unused source uplinks and free destination/spine slots, where a packet waits for its destination to accept it. A blocked output keeps its ID stable. The model allows path reordering and abstracts each packet to one transferable unit. It does not model optical settling time or a transport protocol.

A configuration request stops new launches. Existing output slots stay attached to the old mapping until drained, after which the fabric commits the new mapping. Ingress queues retain their packets across a configuration change. The requester must present a valid mapping only when the configuration-ready signal is high.

## Verification

Identical 128-packet workloads drive the fixed and reconfigured fabrics from leaf 0 to leaf 3. The fixed mapping provides one shared spine. Crossing the first switch gives the pair two. Both testbenches deliver every ID exactly once and to the expected leaf. Fixed service takes 130 cycles and reconfigured service takes 66 cycles, including fill and drain. The resulting throughput ratio is approximately 1.97. A separate distributed workload exercises all eight leaves under periodic output stalls. The reconfiguration test holds an outstanding packet and validates that the mapping changes only after it leaves.

```sh
python scripts/run_tests.py -v clos_ocs_fabric
```

## Exercises

1. Compare several crossbar mappings for multiple hot pairs and measure which pairs lose shared secondary paths.
2. Add optical settling cycles and find the burst length needed to recover the reconfiguration overhead.
