# LR/SC, exponential backoff and a sense barrier

**Topic:** synchronization · **Reference:** Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Chapter 5 §5.5 and Appendix I §I.4. These are original teaching models, not a complete implementation of a particular ISA or cache hierarchy.

`llsc_barrier` accepts one serialized memory command per cycle from one of four cores. Operation 0 loads, 1 loads and reserves a word, 2 performs a conditional store, and 3 performs an ordinary store. A response supplies the old word; `sc_success` is asserted only for a matching live reservation. Every SC consumes its own reservation, including a failed or wrong-address SC. Successful stores invalidate reservations for the addressed word; `invalidations` counts remote reservations cleared, not bus transactions. Reservations are word-granular and the model omits spurious failure, interrupts, eviction and context switches. It is a serialized reference monitor rather than a full coherence implementation.

The same unit has an independent four-core sense-reversing barrier. An arrival toggles that core's local sense and marks it waiting; duplicate arrivals are ignored. The last distinct arrival toggles global sense, clears the wait mask and pulses release. All four cores must participate once per phase and cannot start a new phase before release. The barrier does not model instruction retirement, buffered stores or a memory fence.

The included [snooping-bus lock benchmark](../spinlock_atomic) adds mode 4: TTAS polling followed by LR/SC and an exponential delay after a failed SC. Its base delay doubles up to 32 and is multiplied by core number plus one to stagger retries; a successful acquisition resets it. Mode 5 uses the same LR/SC TTAS without backoff, isolating the effect of the delay. Modes 0 and 1 remain exchange-based TAS and TTAS. A BusRdX is an invalidating bus broadcast; the model counts broadcasts, not the number of individual cached copies invalidated.

Both testbenches check failed SC after a remote store, unrelated-address stores, mismatched addresses, local writes, consumption of a successful reservation and invalidation of multiple reservations. They run two barrier phases in different orders with a duplicate arrival. Four cores then perform eight protected increments each. All four lock configurations complete 32 increments with at most one core inside the critical section. In this deterministic workload, BusRdX broadcasts are 127 for TAS, 101 for exchange TTAS, 53 for LR/SC TTAS without delay and 28 with backoff; respective cycle counts are 738, 964, 930 and 841. These are model-specific results, not a general guarantee that backoff improves latency or traffic.

```sh
python scripts/run_tests.py llsc_backoff_barrier spinlock_atomic
```
