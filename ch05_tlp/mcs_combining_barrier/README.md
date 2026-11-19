# MCS Lock and Combining-Tree Barrier

**Reference** — Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Appendix I §I.4. This example models synchronization state and message counts for 2, 4 and 8 cores.

## Lock handoff

In MCS mode, a request atomically exchanges its node with the queue tail. If the queue was empty, it acquires the lock. Otherwise it publishes its identity as its predecessor's successor one cycle later. Each core observes its own grant bit. An unlock that sees the tail change before the successor link is visible waits for the link and then passes the grant to exactly one successor. Enqueue serialization resolves simultaneous requests in ascending core order.

Centralized mode models contenders that cache a shared polling line. Each release charges one notification for every waiting core, and arbitration chooses the lowest numbered pending requester. The metric counts messages to waiting cores on unlock. It excludes enqueue exchanges, successor-link publication, local polling, and instruction overhead in both modes. A counted message is a point-to-point notification, so these figures cannot be interpreted as numbers of broadcasts on a shared bus.

## Barrier

The tree represents a complete binary heap and combines two child arrivals per internal node. Each parent advances at most one level per cycle. The root starts release on the next cycle and release proceeds down the tree. A duplicate arrival is ignored within the current phase. After release, a core may participate in the next phase. Centralized mode counts one arrival per core and one notification per core when it releases.

For N cores, the tree sends 4(N−1) messages per phase in this model, with four messages incident on the root. The centralized model sends 2N, all incident on its root. Both totals grow linearly. The tree's last-arrival-to-release delay is 2 log₂(N) + 1 cycles and its root handles constant traffic per phase. The centralized delay is one cycle because this teaching model accepts all arriving bits in parallel. The comparison separates total messages, root traffic and depth.

## Interface and tests

Pulse the request, unlock or arrival bit belonging to a core on a rising clock edge. A core may request again after release and must wait for barrier release before arriving for its next phase. The barrier and lock have independent state. Reset clears all state and counters. The supported configurations are powers of two from 2 through 8.

Both testbenches check mutual exclusion, acquisition order, a one-cycle unlock during delayed successor publication, an uncontended unlock, and two reusable barrier phases with opposite arrival orders and a duplicate. For one saturated drain, MCS counts N−1 handoff notifications and centralized polling counts N(N−1)/2. The tests assert every intermediate count as well as barrier totals, release cycles and pulse width.

```sh
python scripts/run_tests.py -v mcs_combining_barrier
```

## Exercises

1. Replace lowest-ID request arbitration with round robin and rerun the contended drain.
2. Add bounded arrival bandwidth at the centralized root and measure how its release latency changes.
