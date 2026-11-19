# MOESI and False Sharing

**Reference** — Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Chapter 5 §§5.2–5.3. The model has four private two-line direct-mapped caches, eight backing lines and two 32-bit words per line.

## Design

The atomic snoop service accepts one word read or write each cycle. A read miss consults peers before using backing memory. A Modified peer supplies its dirty line, becomes Owned and defers write-back. The requester becomes Shared. Further readers receive data from the Owned peer. A writer obtains the complete line, invalidates other copies, and becomes Modified. Replacing a dirty Modified or Owned line writes the complete line to memory. The requesting core's resulting state and every cache slot's state are exposed for observation.

The miss output describes tag misses. An upgrade on a valid local tag is a hit under that definition. When a store invalidates a peer, the classifier remembers the written word and accumulates words written until the invalidated peer refills. On that peer's next miss, a match on the requested word counts as true sharing. A different word on the same invalidated line counts as false sharing. With no recorded invalidation, first touches are cold. A two-entry fully associative LRU shadow distinguishes capacity misses from conflicts on later touches. This makes the classification precedence explicit even when the working set also exceeds the real cache.

## Verification

Both HDL testbenches check a Modified-to-Owned read and a second dirty-peer read with zero memory writes, then evict the owner and verify that the dirty word survives. They exercise cold, conflict, capacity and true-sharing categories, and check that an adjacent-word ping-pong produces ten false-sharing misses. The same writes to padded addresses produce zero. A separate read checks that ownership transfers preserve an untouched neighbor word.

```sh
python scripts/run_tests.py -v moesi_false_sharing
```

## Exercises

1. Increase the line size and compare the false-sharing counter for different data layouts.
2. Add a non-atomic address and data path and check owner eviction during an outstanding read.
