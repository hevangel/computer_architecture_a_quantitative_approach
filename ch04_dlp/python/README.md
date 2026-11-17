# Roofline and affine loop dependence

`roofline_loop_model.py` computes a ridge point and a memory- or compute-bound
throughput ceiling from measured or hypothetical peak throughput, bandwidth,
and arithmetic intensity. It also offers an integer GCD alias test and a bounded
single-loop search and a multidimensional affine-nest search for a pair of
distinct iterations that access the same linear element. The GCD test can rule out equality but cannot by itself establish a
bounded dependence; a real data dependence also requires at least one write.
Each bounded search costs O(number of iterations) time and space; for nests this
is the product of the trip counts. Nest bounds are rectangular Python ranges, and
expressions use one linear address, so triangular bounds, nonlinear subscripts,
compiler transformations and cache effects are outside the model.

`classify_affine_dependences` accepts named, ordered `AffineAccess` reads and
writes and returns actual witnesses for flow, anti and output conflicts, both
within and across iterations. It reports a separate witness for each direction
vector and preserves the execution order of descending ranges. Distances are
index-value differences, not loop-trip counts. Equal array names represent the
same storage; callers must model aliases and overlapping byte ranges explicitly.
The analysis includes transitive conflicts, not just the last writer. It retains
prior events and can take quadratic time and linear storage in the number of
access events; it is intended for bounded teaching examples.

```python
from roofline_loop_model import AffineAccess, classify_affine_dependences

accesses = [AffineAccess("read", "A", "read", (1,), -1),
            AffineAccess("write", "A", "write", (1,))]
flow = classify_affine_dependences(accesses, (range(4),))[0]
assert (flow.kind, flow.source_iteration, flow.target_iteration) == ("flow", (0,), (1,))
```

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 4, sections 4.3–4.5 and 4.7. Inputs in
most tests are synthetic. A test also reproduces the 6th edition (2017), §4.3,
Figure 4.11, p. 341 comparison of the NEC SX-9 and Core i7 920: at 0.25
operations per byte the ceilings are 40.5 and 4.1 GFLOP/s, respectively; at
intensity 4 they are 102.4 and 42.66 GFLOP/s. These are ceilings, not measured
kernel performance. The tests also apply the model to the Core i7 920 and GTX 280
parameters in 5th edition, §4.7, Figure 4.28, p. 355; 6th edition, §4.7, Figure 4.28, p. 381; and 7th edition, Figure 4.31. Those figures use the same underlying processor parameters, so these are not independent hardware measurements. At intensity 0.5, the
double-precision ceilings are 8.2 and 63.5 GFLOP/s; at intensity 4 they are
42.66 and 78 GFLOP/s. The computed single-precision ceilings at intensity 4 are
65.6 and 508 GFLOP/s using the listed bandwidths; the figure caption gives
rounded values based on different rounding. A sample SAXPY update assumes two
operations and twelve bytes of DRAM traffic (two float reads and one write),
so its ideal single-precision ceilings are about 2.73 and 21.17 GFLOP/s. This
is an illustrative upper bound, not a prediction of the measured benchmark:
cache reuse, write allocation, non-coalesced accesses and instruction mix can
change the traffic or attainable throughput. The comparison helper assumes the
same intensity for all targets; supply separate comparisons if traffic differs.

Run from the repository root:

```sh
python -m unittest discover -s ch04_dlp/python -p 'test_*.py' -v
```


## Banked vector-memory reference

`vector_memory_reference.py` is a software oracle for the planned banked
vector-memory RTL. It strip-mines an arbitrary vector into bounded chunks,
schedules at most one word per bank per cycle, and simulates indexed loads and
stores in element order within each bank. It reports ideal and actual service
cycles, conflict stalls, optional per-strip startup and a lane trace. Its
asymptotic helper computes a rate and half-performance length from an explicitly
supplied fixed-rate/startup model; it is not a measurement of a real machine.

For 45 unit-stride words with 8 banks and MVL 16, the reference processes
16+16+13 elements in six ideal service cycles with no bank stalls. Sixteen
stride-8 words all map to one bank and take 16 cycles instead of two. Tests
also cover sparse gather/scatter and duplicate-address ordering. The model
assumes one-cycle single-port banks, no bank recovery delay, no cache and no
overlap between strips. See Hennessy and Patterson, 6th edition (2017),
Chapter 4 §4.2 and Appendix G §§G.2–G.4. The [SystemVerilog and VHDL implementation](../vector_bank_gather_strip)
uses a bounded 64-element command.
