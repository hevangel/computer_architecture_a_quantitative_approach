# I/O queueing and rebuild-window model

These standard-library models illustrate Little's Law, M/M/1, M/G/1 and M/M/m
steady-state queues, a simplified disk access time, and the probability of
additional independent disk failures during a fixed RAID-5 or RAID-6 rebuild,
and a separate repairable-array mean time to data loss (MTTDL) model.
For background see Hennessy and Patterson, *Computer Architecture: A
Quantitative Approach*, 7th edition (2025), Appendix D, sections D.4–D.5.

Queue arrival and service rates use reciprocal units of time. M/G/1 accepts the
second moment of service time, not its variance. The disk model assumes a mean
half-rotation wait and seek time `a + b * sqrt(distance)`; it ignores scheduling
and request locality. The RAID probability is conditional on an initial failure:
AFR is converted to a constant exponential failure hazard and remaining disks
fail independently during a fixed rebuild interval. It omits latent errors,
correlated failures and overlapping repairs. The MTTDL model instead uses an
exponential repair time and permits repeated transitions between degraded
states; it repairs one disk at a time and assumes repaired disks are as new.
It excludes common-cause failures and latent sector errors. These two rebuild
assumptions describe different models and should not be mixed.

Run from the repository root:

```sh
python -m unittest discover -s appD_storage/python -p 'test_*.py' -v
```

The tests check independently calculated queueing values, a disk-time example,
binomial failure probabilities, small probabilities and invalid inputs. These
Python tests are separate from the hardware tests.
