"""Roofline ceilings and one-dimensional affine dependence checks.

The GCD test is a necessary, not sufficient, condition for bounded loops. The
bounded checker enumerates iterations and reports an actual loop-carried pair.
"""

from math import gcd, isfinite


def roofline(peak_ops_per_second, bandwidth_bytes_per_second, ops_per_byte):
    """Return (ridge point in ops/byte, attainable ops/s, limiting resource)."""
    if not isfinite(peak_ops_per_second) or peak_ops_per_second <= 0:
        raise ValueError("peak throughput must be finite and positive")
    if not isfinite(bandwidth_bytes_per_second) or bandwidth_bytes_per_second <= 0:
        raise ValueError("bandwidth must be finite and positive")
    if not isfinite(ops_per_byte) or ops_per_byte < 0:
        raise ValueError("intensity must be finite and nonnegative")
    ridge = peak_ops_per_second / bandwidth_bytes_per_second
    return ridge, min(peak_ops_per_second, bandwidth_bytes_per_second * ops_per_byte), (
        "memory" if ops_per_byte < ridge else "compute" if ops_per_byte > ridge else "balanced"
    )


def gcd_may_alias(a, b, c, d):
    """Could a*i+b equal c*j+d over unbounded integer i and j?"""
    if any(isinstance(x, bool) or not isinstance(x, int) for x in (a, b, c, d)):
        raise ValueError("affine coefficients must be integers")
    divisor = gcd(a, c)
    return d == b if divisor == 0 else (d - b) % divisor == 0


def loop_carried_witness(a, b, c, d, start, stop, step=1):
    """Return (i, j) with i before j and a*i+b == c*j+d, or None.

    Bounds and iteration ordering follow Python's range. The first expression
    is an access at i and the second an access at j. The caller must determine
    whether either access writes before calling the pair a data dependence.
    """
    if any(isinstance(x, bool) or not isinstance(x, int) for x in (start, stop, step)) or step == 0:
        raise ValueError("range arguments must be integers with nonzero step")
    if not gcd_may_alias(a, b, c, d):
        return None
    earliest = {}
    for j in range(start, stop, step):
        target = c * j + d
        if target in earliest:
            return earliest[target], j
        earliest.setdefault(a * j + b, j)
    return None
