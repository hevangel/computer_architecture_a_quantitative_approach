"""Idealized queueing, disk service, and independent-failure RAID models.

Time units must be consistent within a calculation. Queueing formulas describe
steady state; the RAID model deliberately excludes correlated failures, latent
sector errors, and repair of other failed drives during the rebuild window.
"""

from math import exp, expm1, isfinite, log1p, sqrt


def _nonnegative(value, name):
    if not isfinite(value) or value < 0:
        raise ValueError(f"{name} must be finite and nonnegative")
    return value


def _positive(value, name):
    if not isfinite(value) or value <= 0:
        raise ValueError(f"{name} must be finite and positive")
    return value


def littles_law(arrival_rate, mean_time):
    """Mean number in a stable system: arrival rate times mean time."""
    return _nonnegative(arrival_rate, "arrival_rate") * _nonnegative(mean_time, "mean_time")


def mg1(arrival_rate, mean_service, second_moment):
    """Return (utilization, mean queue wait, mean response) for an M/G/1 queue.

    second_moment is E[S**2] in squared time units, not variance.
    """
    _nonnegative(arrival_rate, "arrival_rate")
    _positive(mean_service, "mean_service")
    _nonnegative(second_moment, "second_moment")
    if second_moment < mean_service ** 2 * (1 - 1e-12):
        raise ValueError("second moment cannot be smaller than mean squared")
    utilization = arrival_rate * mean_service
    if utilization >= 1:
        raise ValueError("queue must have utilization below one")
    wait = arrival_rate * second_moment / (2 * (1 - utilization))
    return utilization, wait, wait + mean_service


def mm1(arrival_rate, service_rate):
    """Return utilization, mean queue wait and mean response for M/M/1."""
    _positive(service_rate, "service_rate")
    return mg1(arrival_rate, 1 / service_rate, 2 / service_rate ** 2)


def mmm(arrival_rate, service_rate, servers):
    """Return utilization, Erlang-C wait probability, queue wait and response.

    Uses the Erlang-B recurrence to avoid factorial overflow for large pools.
    service_rate is the rate of each server.
    """
    _nonnegative(arrival_rate, "arrival_rate")
    _positive(service_rate, "service_rate")
    if isinstance(servers, bool) or not isinstance(servers, int) or servers < 1:
        raise ValueError("servers must be a positive integer")
    offered = arrival_rate / service_rate
    utilization = offered / servers
    if utilization >= 1:
        raise ValueError("queue must have utilization below one")
    blocking = 1.0
    for n in range(1, servers + 1):
        blocking = offered * blocking / (n + offered * blocking)
    probability_wait = blocking / (1 - utilization + utilization * blocking)
    wait = probability_wait / (servers * service_rate - arrival_rate)
    return utilization, probability_wait, wait, wait + 1 / service_rate


def disk_service_time(distance, seek_fixed, seek_sqrt_factor, rotational_period, byte_count, bytes_per_time):
    """Mean service time: a+b*sqrt(distance), half a revolution, transfer."""
    for name, value in (("distance", distance), ("seek_fixed", seek_fixed),
                        ("seek_sqrt_factor", seek_sqrt_factor), ("rotational_period", rotational_period),
                        ("byte_count", byte_count)):
        _nonnegative(value, name)
    _positive(bytes_per_time, "bytes_per_time")
    return seek_fixed + seek_sqrt_factor * sqrt(distance) + rotational_period / 2 + byte_count / bytes_per_time


def rebuild_loss_probability(disks, parity_disks, annual_failure_rate, rebuild_years):
    """Probability of losing a degraded RAID-5/6 array during a fixed rebuild.

    One disk has already failed. Each remaining disk has a constant independent
    exponential hazard specified by AFR = P(failure within one year). RAID-5
    loses data if at least one other disk fails; RAID-6 if at least two do.
    """
    if isinstance(disks, bool) or not isinstance(disks, int) or parity_disks not in (1, 2) or disks <= parity_disks:
        raise ValueError("invalid disk or parity count")
    if not isfinite(annual_failure_rate) or not 0 <= annual_failure_rate < 1:
        raise ValueError("annual_failure_rate must be in [0, 1)")
    _nonnegative(rebuild_years, "rebuild_years")
    # log1p retains precision for small failure rates; expm1 avoids cancellation.
    p = -expm1(log1p(-annual_failure_rate) * rebuild_years)
    remaining = disks - 1
    if parity_disks == 1:
        return -expm1(remaining * log1p(-p)) if p < 1 else 1.0
    if p == 1:
        return 1.0 if remaining >= 2 else 0.0
    # For a large expected count, the complement is well-conditioned and
    # avoids underflow in a recurrence initialized with P(no failures).
    if remaining * p > 1:
        log_zero = remaining * log1p(-p)
        return max(0.0, 1 - exp(log_zero) * (1 + remaining * p / (1 - p)))
    # For small p, sum the tail directly to avoid subtractive cancellation.
    probability = 0.0
    term = (1 - p) ** remaining
    for k in range(1, remaining + 1):
        term *= (remaining - k + 1) / k * p / (1 - p)
        if k >= 2:
            probability += term
    return min(probability, 1.0)


def raid_mttdl(disks, parity_disks, annual_failure_rate, mean_repair_years):
    """Mean years to array data loss from healthy state in a birth-death model.

    Independent working disks have an exponential lifetime with annual failure
    probability AFR. One failed disk at a time is repaired, exponentially, at
    rate 1/mean_repair_years. A failure in state parity_disks absorbs the chain.
    Repairs return disks to an as-new state. Common-cause failures and latent
    sector errors are excluded; this is not a fixed-duration rebuild model.
    """
    if isinstance(disks, bool) or not isinstance(disks, int) or parity_disks not in (1, 2) or disks <= parity_disks:
        raise ValueError("invalid disk or parity count")
    if not isfinite(annual_failure_rate) or not 0 < annual_failure_rate < 1:
        raise ValueError("annual_failure_rate must be in (0, 1)")
    _positive(mean_repair_years, "mean_repair_years")
    failure_rate = -log1p(-annual_failure_rate)
    repair_rate = 1 / mean_repair_years
    # For adjacent-state hitting times, d_i=(1+repair_rate*d_(i-1))/birth_i.
    adjacent = 0.0
    total = 0.0
    for failed in range(parity_disks + 1):
        adjacent = (1 + (repair_rate * adjacent if failed else 0)) / ((disks - failed) * failure_rate)
        total += adjacent
    return total
