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

The tests reproduce the 6th edition (2017), Appendix D.5, pp. 884–886:
40 requests/s yield 100 ms response for one 20 ms disk, 16.7 ms for a 10 ms
disk, and 23.8 ms for two 20 ms disks sharing a read queue. These comparisons
assume Poisson arrivals, exponential service and a shared FIFO queue. Tests also
check the rise in response time near saturation, a disk-time example,
binomial failure probabilities, small probabilities and invalid inputs. These
Python tests are separate from the hardware tests.


## RAID-6 and symbol-code reference

`raid6_chipkill_ref.py` supplies a software reference for the APPD-1
hardware. Four data bytes use GF(256) P/Q parity to recover any one or two
known erasures. An independent ten-nibble code uses two GF(16) check symbols
to locate and correct one corrupted nibble. It is an educational symbol code,
not a particular commercial Chipkill implementation. Multiple corruptions
can be miscorrected and require an outer integrity check. The tests compare
field multiplication with polynomial long division, exercise every erasure
pair on multiple stripes, and inject all 15 nonzero error patterns in each
symbol position. The same vectors also exercise the SV and VHDL implementations. For context see Hennessy and Patterson, 6th edition (2017),
Appendix D, section D.2, and 7th edition (2025), Chapter 2, section 2.2.
