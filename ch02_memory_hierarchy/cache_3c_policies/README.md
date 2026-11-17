# Cache miss classification and replacement policies

**Topic:** cache misses and replacement · **Reference:** Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Appendix B §B.3. The models are original teaching examples; they do not reproduce textbook figures or prose.

A reference to a previously unseen block is compulsory. For a seen block, the evaluator compares the access with a fully associative LRU shadow of the same total capacity: a shadow miss is classified as capacity, and a shadow hit as conflict. For non-LRU policies the latter category also includes replacement-policy misses, so it is labelled **conflict/policy** rather than attributing every such miss solely to mapping.

`SETS` chooses the number of sets, `ASSOC` selects one through four ways, and `POLICY` selects LRU (0), FIFO (1), deterministic LFSR random (2), or a four-leaf binary-tree pseudo-LRU (3). Unused pseudo-LRU leaves are skipped for three-way caches. Random uses an 8-bit LFSR seeded to 1, updated on each miss, with taps 7, 5, 4, 3; its state modulo associativity chooses a full-set victim. Invalid ways are filled first. The 8-bit input is a block number, not a byte address. A 256-entry exact seen table and a same-capacity shadow cover this finite address space. Timestamps are 32 bits, so reset before 2^32 accesses to avoid replacement-order wraparound. The model reports one classification per accepted access; it does not model data, dirty lines, latency or coherence.

Both HDL testbenches replay three independent 256-access traces and compare the classification of every access and the cumulative counts against [the Python reference](python/cache_reference.py), for direct-mapped, two-, three- and four-way LRU four-way FIFO, random and pseudo-LRU, plus smaller pseudo-LRU and three-way random configurations. In the thrashing trace the four-way cache has four compulsory misses and no conflict misses, versus four compulsory and 252 conflict misses in the equal-capacity direct-mapped cache. The other traces exercise capacity pressure and replacement differences. The reference also has hand-checked unit tests.

```sh
python scripts/run_tests.py cache_3c_policies
python -m unittest discover -s ch02_memory_hierarchy/cache_3c_policies/python
```

Try a trace with a hot working set plus one occasional streaming block. Compare FIFO and LRU, then vary the number of sets while keeping total capacity constant.
