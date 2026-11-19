# Quantitative fundamentals

`quant_eval_suite.py` models wafer yield and known-good-die package costs; series and parallel MTTF, including repairable redundancy; independent component availability; fixed-work DVFS energy; operational and allocated embodied carbon; and arithmetic, weighted arithmetic, harmonic and geometric benchmark means and population geometric standard deviation.

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 7th edition (2025), Chapter 1 §§1.5–1.8. The test cost inputs are synthetic. Wafer packing is approximate, dies are known-good, and each failed package consumes its parts. `uniform_chiplet_cost` models a package of identical chiplets. `chiplet_break_even_density` uses bisection to find one cost crossing inside a user-supplied defect-density bracket; it does not establish uniqueness or search outside that bracket. For the test case, the crossing is approximately 0.003086580213699 defects/mm² and both packages cost approximately 216.984 in the caller's currency. A separately evaluated high-precision cubic equation provides the reference value.

The nonrepairable parallel MTTF assumes independent exponential lifetimes. The separate repairable-pair model assumes independent exponential failures and repair, starts with both units operational, and stops at the first outage; it excludes common-cause failures. For the power-supply example in the 6th edition (2017), §1.7, pp. 39–40, 200,000-hour component MTTF and 24-hour mean repair give approximately 833.6 million hours to first outage (4,168 times one component). The textbook's rare-failure approximation gives roughly 830 million hours (4,150 times). The 7th edition extraction retains the 4,150-times conclusion but omits the example's calculation and inputs, so those inputs are cited to the 6th edition. Parallel availability assumes independent component states and is a different metric.

DVFS treats capacitance, switching activity and leakage as fixed, so the illustrated cubic dynamic-power relationship requires frequency proportional to voltage. The carbon model is an inventory sum, not a full life-cycle assessment.

From the repository root:

```sh
python -m unittest discover -s ch01_fundamentals/python -p 'test_*.py' -v
```

The tests cover closed-form values, validation, a bracketed cost crossover and numerical convergence. They are separate from the HDL test count.
