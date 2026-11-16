"""Small, unit-explicit models for warehouse-scale computing experiments.

Service times are supplied by the caller. The separate two-server simulation
models FIFO contention and instantaneous cancellation, not failures or networks.
"""

from math import ceil, isfinite
from collections import deque
from heapq import heappop, heappush
from itertools import count


def _nonnegative(value, name):
    if not isfinite(value) or value < 0:
        raise ValueError(f"{name} must be finite and nonnegative")
    return value


def pue(facility_kw, it_kw):
    """Facility power / IT power, measured over the same interval."""
    _nonnegative(facility_kw, "facility_kw")
    if not isfinite(it_kw) or it_kw <= 0 or facility_kw < it_kw:
        raise ValueError("IT power must be positive and no greater than facility power")
    return facility_kw / it_kw


def total_cost(server_capex, facility_capex, annual_opex, years):
    """Undiscounted total ownership cost for the specified period, in one currency."""
    for name, value in (("server_capex", server_capex), ("facility_capex", facility_capex),
                        ("annual_opex", annual_opex), ("years", years)):
        _nonnegative(value, name)
    return server_capex + facility_capex + annual_opex * years


def energy_cost(it_kw, facility_pue, hours, price_per_kwh):
    """Facility energy cost for constant average IT power and PUE."""
    for name, value in (("it_kw", it_kw), ("hours", hours), ("price_per_kwh", price_per_kwh)):
        _nonnegative(value, name)
    if not isfinite(facility_pue) or facility_pue < 1:
        raise ValueError("PUE must be finite and at least one")
    return it_kw * facility_pue * hours * price_per_kwh


def carbon_kg(facility_kwh, grid_kg_per_kwh, embodied_kg):
    """Operational and allocated embodied emissions, in kg CO2e."""
    for name, value in (("facility_kwh", facility_kwh), ("grid_kg_per_kwh", grid_kg_per_kwh),
                        ("embodied_kg", embodied_kg)):
        _nonnegative(value, name)
    return facility_kwh * grid_kg_per_kwh + embodied_kg


def transfer_time(latency_seconds, bytes_count, bytes_per_second):
    """Serial latency plus transfer time for one request (no contention)."""
    _nonnegative(latency_seconds, "latency_seconds")
    _nonnegative(bytes_count, "bytes_count")
    if not isfinite(bytes_per_second) or bytes_per_second <= 0:
        raise ValueError("bytes_per_second must be finite and positive")
    return latency_seconds + bytes_count / bytes_per_second


def fanout_latency(service_times, hedge_times=None, hedge_delay=0):
    """Latency of a parallel fan-out; optionally launch one replica per slow leaf.

    Each hedge starts at hedge_delay if its primary has not completed. Inputs are
    service durations, not completion timestamps. Outstanding work is ignored.
    """
    primary = list(service_times)
    if not primary:
        raise ValueError("at least one leaf is required")
    _nonnegative(hedge_delay, "hedge_delay")
    for value in primary:
        _nonnegative(value, "service time")
    if hedge_times is None:
        return max(primary)
    replicas = list(hedge_times)
    if len(replicas) != len(primary):
        raise ValueError("each primary needs one replica duration")
    for value in replicas:
        _nonnegative(value, "replica time")
    return max(min(first, hedge_delay + second) for first, second in zip(primary, replicas))


def percentile(samples, percentile_value):
    """Nearest-rank percentile, with p in (0, 100]."""
    ordered = sorted(samples)
    if not ordered or not isfinite(percentile_value) or not 0 < percentile_value <= 100:
        raise ValueError("nonempty samples and percentile in (0, 100] required")
    for value in ordered:
        _nonnegative(value, "sample")
    return ordered[ceil(percentile_value / 100 * len(ordered)) - 1]


def simulate_replicas(requests, strategy="primary", hedge_delay=0):
    """Simulate two FIFO servers handling independent logical requests.

    requests is an iterable of (arrival_time, service_on_server_0,
    service_on_server_1), in arbitrary order. Primary sends to server 0;
    hedged sends to server 1 after hedge_delay unless already complete; tied
    queues on both, cancelling a queued sibling as soon as either starts.
    Completion cancels a running or queued sibling immediately. Service times
    must be positive. Return response times in input order, busy time consumed
    by both servers, and numbers of replicas submitted and started.

    All arrivals, completions and hedge timers at a given time are processed
    before dispatch, with completions first. Dispatch is ordered by server ID.
    There is no network or cancellation delay, failure, or service preemption
    except cancellation of the losing replica.
    """
    if strategy not in ("primary", "hedged", "tied"):
        raise ValueError("unknown strategy")
    _nonnegative(hedge_delay, "hedge_delay")
    jobs = list(requests)
    for arrival, first, second in jobs:
        _nonnegative(arrival, "arrival")
        for duration in (first, second):
            if not isfinite(duration) or duration <= 0:
                raise ValueError("service durations must be finite and positive")

    queues = [deque(), deque()]
    running = [None, None]  # (job, start time, generation)
    queued = [[False, False] for _ in jobs]
    tied_started = [False] * len(jobs)
    done = [False] * len(jobs)
    responses = [None] * len(jobs)
    events = []
    sequence = count()
    generation = count()
    submitted = started = 0
    busy_time = 0.0

    def schedule(when, priority, kind, job, server=-1, token=-1):
        heappush(events, (when, priority, next(sequence), kind, job, server, token))

    def submit(job, server, now):
        nonlocal submitted
        submitted += 1
        queued[job][server] = True
        queues[server].append(job)
        schedule(now, 2, "dispatch", -1, server)

    for job, (arrival, _, _) in enumerate(jobs):
        schedule(arrival, 1, "arrival", job)

    while events:
        now, _, _, kind, job, server, token = heappop(events)
        if kind == "arrival":
            submit(job, 0, now)
            if strategy == "tied":
                submit(job, 1, now)
            elif strategy == "hedged":
                schedule(now + hedge_delay, 1, "hedge", job)
        elif kind == "hedge":
            if not done[job]:
                submit(job, 1, now)
        elif kind == "dispatch":
            if running[server] is not None:
                continue
            while queues[server]:
                candidate = queues[server].popleft()
                if not queued[candidate][server] or done[candidate]:
                    continue
                queued[candidate][server] = False
                if strategy == "tied" and tied_started[candidate]:
                    continue
                if strategy == "tied":
                    tied_started[candidate] = True
                    queued[candidate][1 - server] = False
                token = next(generation)
                running[server] = (candidate, now, token)
                started += 1
                schedule(now + jobs[candidate][server + 1], 0, "finish", candidate, server, token)
                break
        elif kind == "finish":
            current = running[server]
            if current is None or current[2] != token:
                continue  # completion of a cancelled replica
            busy_time += now - current[1]
            running[server] = None
            done[job] = True
            responses[job] = now - jobs[job][0]
            other = 1 - server
            queued[job][other] = False
            if running[other] is not None and running[other][0] == job:
                busy_time += now - running[other][1]
                running[other] = None
                schedule(now, 2, "dispatch", -1, other)
            schedule(now, 2, "dispatch", -1, server)
    return {"response_times": responses, "busy_time": busy_time,
            "replicas_submitted": submitted, "replicas_started": started}
