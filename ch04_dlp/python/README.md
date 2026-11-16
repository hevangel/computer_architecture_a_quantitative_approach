# Roofline and affine loop dependence

`roofline_loop_model.py` computes a ridge point and a memory- or compute-bound
throughput ceiling from measured or hypothetical peak throughput, bandwidth,
and arithmetic intensity. It also offers an integer GCD alias test and a bounded
single-loop search for a pair of distinct iterations that access the same
element. The GCD test can rule out equality but cannot by itself establish a
bounded dependence; a real data dependence also requires at least one write.
The bounded search costs O(number of iterations) time and space. It does not
model multidimensional nests, compiler transformations, or cache effects.

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 4, sections 4.3–4.5 and 4.7. Inputs in
the tests are synthetic, not measurements of the systems in the textbook.

Run from the repository root:

```sh
python -m unittest discover -s ch04_dlp/python -p 'test_*.py' -v
```
