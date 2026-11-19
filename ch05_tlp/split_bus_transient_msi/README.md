# Split-Transaction MSI for a Contended Line

**Reference** — Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Appendix I §I.7. This example models two cores and one shared word. It gives the address and data phases separate timing and permits a pending request per core. The address arbiter serializes transactions to the shared line.

## Protocol

Each request contains a read, full-word write, or eviction. A valid request is captured when its core's ready bit is high. Each core waits for its response pulse before submitting another request. The controller starts data service after the configured delay and can hold the response while `allow_data` is low. A pending request retains its operation and write value throughout the wait.

The controller exposes the following intermediate states.

| State | Meaning |
| --- | --- |
| IM_AD | Invalid, waiting to order a read-exclusive address |
| IM_D | Read-exclusive ordered, waiting to complete the write |
| SM_AD | Shared, waiting to order an upgrade |
| MI_A | Dirty eviction pending or awaiting acknowledgement |
| IS_D | Read address ordered, waiting for fill data |

When two sharers request upgrades together, round-robin arbitration orders one first. Its snoop turns the other core's SM_AD into IM_AD and retains the losing write in that core's pending slot. Once the first write completes, the loser issues a read-exclusive transaction against the current state. Dirty data are written back if a peer read downgrades a modified line or a peer request invalidates it. The model also supports a dirty eviction with a separate completion pulse.

The address arbiter can serve other pending operations only after the current transaction completes. This is a single-line ordering model with centralized snoop handling. It does not model interleaved outstanding transactions on different lines, byte masks, wire-level NACK messages or a physical interconnect.

## Verification

The two testbenches first install shared copies, then inject simultaneous upgrades and hold the first data response under backpressure. They check transient states, both response values in bus order, the losing core's fallback, and a later read of the final value. They also check explicit dirty eviction and disallow two modified copies at every observed edge. Both finish at 376 ns.

```sh
python scripts/run_tests.py -v split_bus_transient_msi
```

## Exercises

1. Add separate per-line transaction tracking and allow data responses for different lines to arrive out of order.
2. Replace the centralized snoop observation with explicit request and acknowledgement channels and test arbitration under backpressure.
