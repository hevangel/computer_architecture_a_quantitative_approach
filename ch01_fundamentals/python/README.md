# Quantitative fundamentals

`quant_eval_suite.py` contains idealized wafer yield and known-good-die package
cost models; series and two-component parallel MTTF; independent component
availability; fixed-work DVFS energy; operational and allocated embodied carbon;
and arithmetic, weighted arithmetic, harmonic and geometric benchmark means and
population geometric standard deviation.

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 1, sections 1.5–1.8. The test values are
synthetic. Wafer packing is approximate, dies are known-good, and each failed
package consumes its parts. Parallel MTTF assumes independent exponential
lifetimes without repair; parallel availability assumes independent component
states. DVFS treats capacitance, switching activity and leakage as fixed, so the
illustrated cubic power relationship requires frequency proportional to voltage.
The carbon model is an inventory sum, not a full life-cycle assessment.

From the repository root:

```sh
python -m unittest discover -s ch01_fundamentals/python -p 'test_*.py' -v
```

The tests use closed-form examples and synthetic low- and high-defect cases to
illustrate a cost crossover; they are separate from the HDL test count.
