"""Small, unit-explicit models for warehouse-scale computing experiments.

Service times are supplied by the caller. The separate two-server simulation
models FIFO contention and instantaneous cancellation, not failures or networks.
"""

from math import ceil, expm1, isfinite, log1p, fsum
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


def server_power_kw(server_count, idle_watts, peak_watts, utilization):
    """Linear server power model; utilization is a fraction in [0, 1].

    Identical servers stay powered on even at zero utilization. This model does
    not estimate power consumed by networking, storage, or other IT equipment.
    """
    if isinstance(server_count, bool) or not isinstance(server_count, int) or server_count < 0:
        raise ValueError("server_count must be a nonnegative integer")
    for name, value in (("idle_watts", idle_watts), ("peak_watts", peak_watts)):
        _nonnegative(value, name)
    if peak_watts < idle_watts:
        raise ValueError("peak power must be at least idle power")
    if not isfinite(utilization) or not 0 <= utilization <= 1:
        raise ValueError("utilization must be between zero and one")
    return server_count * (idle_watts + utilization * (peak_watts - idle_watts)) / 1000


def fleet_tco(server_count, server_price, lifetime_years, facility_capacity_kw,
              facility_price_per_watt, facility_lifetime_years, facility_pue,
              price_per_kwh, utilization_periods, annual_other_opex=0):
    """Annualized, undiscounted server/facility cost plus one year's energy.

    utilization_periods contains (hours, IT kW) pairs that must total exactly
    8760 hours. Facility capacity is provisioned IT power, in kW; the facility
    price is per watt of that capacity. Server and facility costs are evenly
    amortized across their respective lifetimes. Energy uses a constant PUE;
    annual_other_opex excludes that energy to avoid double-counting. The result
    is an annual average, not a cash-flow or discounted net-present-value model.
    """
    if isinstance(server_count, bool) or not isinstance(server_count, int) or server_count < 0:
        raise ValueError("server_count must be a nonnegative integer")
    for name, value in (("server_price", server_price),
                        ("facility_capacity_kw", facility_capacity_kw),
                        ("facility_price_per_watt", facility_price_per_watt),
                        ("price_per_kwh", price_per_kwh),
                        ("annual_other_opex", annual_other_opex)):
        _nonnegative(value, name)
    for value in (lifetime_years, facility_lifetime_years):
        if not isfinite(value) or value <= 0:
            raise ValueError("lifetimes must be finite and positive")
    if not isfinite(facility_pue) or facility_pue < 1:
        raise ValueError("PUE must be finite and at least one")
    periods = list(utilization_periods)
    for hours, it_kw in periods:
        _nonnegative(hours, "hours")
        _nonnegative(it_kw, "it_kw")
        if it_kw > facility_capacity_kw:
            raise ValueError("IT load exceeds facility capacity")
    if abs(sum(hours for hours, _ in periods) - 8760) > 1e-8:
        raise ValueError("periods must cover 8760 hours")
    it_kwh = sum(hours * it_kw for hours, it_kw in periods)
    facility_kwh = it_kwh * facility_pue
    server_annual = server_count * server_price / lifetime_years
    facility_annual = facility_capacity_kw * 1000 * facility_price_per_watt / facility_lifetime_years
    energy_annual = facility_kwh * price_per_kwh
    return {"it_kwh": it_kwh, "facility_kwh": facility_kwh,
            "server_amortization": server_annual,
            "facility_amortization": facility_annual,
            "energy_cost": energy_annual, "other_opex": annual_other_opex,
            "annual_total": server_annual + facility_annual + energy_annual + annual_other_opex}


def hierarchy_path(storage_latency_seconds, storage_bytes_per_second,
                   storage_capacity_bytes, server_count, links=()):
    """Describe a tier accessed through serial links with additive fixed latency.

    links is an iterable of (fixed latency in seconds, bandwidth in bytes/s).
    Throughput is bounded by the slowest storage or link component. Latencies
    add; per-byte transfer is modeled as a single pipelined bottleneck, without
    queueing, protocol overhead, or contention. Aggregate capacity assumes all
    servers contribute independent, equally sized storage without replication.
    """
    _nonnegative(storage_latency_seconds, "storage_latency_seconds")
    _nonnegative(storage_capacity_bytes, "storage_capacity_bytes")
    if isinstance(server_count, bool) or not isinstance(server_count, int) or server_count <= 0:
        raise ValueError("server_count must be a positive integer")
    if not isfinite(storage_bytes_per_second) or storage_bytes_per_second <= 0:
        raise ValueError("storage bandwidth must be finite and positive")
    latency = storage_latency_seconds
    bandwidth = storage_bytes_per_second
    for link_latency, link_bandwidth in links:
        _nonnegative(link_latency, "link latency")
        if not isfinite(link_bandwidth) or link_bandwidth <= 0:
            raise ValueError("link bandwidth must be finite and positive")
        latency += link_latency
        bandwidth = min(bandwidth, link_bandwidth)
    return {"latency_seconds": latency, "bytes_per_second": bandwidth,
            "capacity_bytes": storage_capacity_bytes * server_count}


def hierarchy_access_time(paths, fractions, bytes_count=0):
    """Weighted average request time over mutually exclusive hierarchy paths.

    Fractions are unconditional probabilities and must sum to one. Each path
    uses hierarchy_path's latency and bottleneck bandwidth; requests access one
    selected tier, and therefore incur no sequential cache-miss probes.
    """
    paths = list(paths)
    fractions = list(fractions)
    _nonnegative(bytes_count, "bytes_count")
    if not paths or len(paths) != len(fractions):
        raise ValueError("one fraction per path is required")
    for fraction in fractions:
        _nonnegative(fraction, "fraction")
    if abs(sum(fractions) - 1) > 1e-12:
        raise ValueError("fractions must sum to one")
    return sum(fraction * transfer_time(path["latency_seconds"], bytes_count,
                                        path["bytes_per_second"])
               for path, fraction in zip(paths, fractions))


def monthly_capital_payment(principal, annual_interest_rate, months):
    """Monthly level payment for a fully amortized loan at nominal annual rate.

    Interest compounds monthly; principal and payment use the same currency.
    This is a capital-recovery convention, not a prediction of tax or cash flow.
    """
    _nonnegative(principal, "principal")
    _nonnegative(annual_interest_rate, "annual_interest_rate")
    if isinstance(months, bool) or not isinstance(months, int) or months <= 0:
        raise ValueError("months must be a positive integer")
    rate = annual_interest_rate / 12
    if rate == 0:
        return principal / months
    return principal * rate / -expm1(-months * log1p(rate))


def monthly_wsc_cost(critical_it_kw, utilization, facility_pue, price_per_kwh,
                     capital_assets, annual_interest_rate, monthly_people_cost,
                     *, hours_per_month=730, server_count=None):
    """Financed monthly cost of a WSC, separating capital, energy and people.

    capital_assets maps names to (capital cost, amortization months), with all
    amounts in one currency. Critical load is provisioned IT power; utilization
    is the average fraction of that load, and PUE applies to average IT power.
    Monthly energy assumes constant average power and the supplied month length.
    Principal is financed at a nominal annual rate with monthly compounding.
    This is a level-payment scenario, not a complete accounting or tax model.
    """
    for name, value in (("critical_it_kw", critical_it_kw),
                        ("price_per_kwh", price_per_kwh),
                        ("monthly_people_cost", monthly_people_cost),
                        ("hours_per_month", hours_per_month)):
        _nonnegative(value, name)
    if not isfinite(utilization) or not 0 <= utilization <= 1:
        raise ValueError("utilization must be between zero and one")
    if not isfinite(facility_pue) or facility_pue < 1:
        raise ValueError("PUE must be finite and at least one")
    _nonnegative(annual_interest_rate, "annual_interest_rate")
    if server_count is not None and (isinstance(server_count, bool) or
                                     not isinstance(server_count, int) or server_count <= 0):
        raise ValueError("server_count must be a positive integer")
    assets = dict(capital_assets)
    if not assets or any(not isinstance(name, str) or not name for name in assets):
        raise ValueError("capital assets must have nonempty names")
    payments = {name: monthly_capital_payment(amount, annual_interest_rate, months)
                for name, (amount, months) in assets.items()}
    average_it_kw = critical_it_kw * utilization
    facility_kw = average_it_kw * facility_pue
    facility_kwh = facility_kw * hours_per_month
    electricity = facility_kwh * price_per_kwh
    total = fsum(payments.values()) + electricity + monthly_people_cost
    return {"capital_total": fsum(amount for amount, _ in assets.values()),
            "capital_payments": payments, "average_it_kw": average_it_kw,
            "facility_kw": facility_kw, "facility_kwh": facility_kwh,
            "electricity": electricity, "people": monthly_people_cost,
            "monthly_total": total,
            "cost_per_server_hour": None if server_count is None or hours_per_month == 0
                                    else total / (server_count * hours_per_month)}


def four_m_carbon(baseline_it_kwh, model_energy_reduction, machine_energy_reduction,
                  baseline_pue, target_pue, baseline_grid_kg_per_kwh,
                  target_grid_kg_per_kwh, *, baseline_embodied_kg=0, target_embodied_kg=0):
    """Compare model, machine, mechanization and map choices for equal work.

    Model and machine reductions are measured multiplicative IT-energy factors,
    not independent predictions. Mechanization changes PUE; map changes the
    grid's carbon intensity. Embodied values are caller-allocated to the work
    and are added separately rather than reduced by operational improvements.
    """
    for name, value in (("baseline_it_kwh", baseline_it_kwh),
                        ("baseline_grid_kg_per_kwh", baseline_grid_kg_per_kwh),
                        ("target_grid_kg_per_kwh", target_grid_kg_per_kwh),
                        ("baseline_embodied_kg", baseline_embodied_kg),
                        ("target_embodied_kg", target_embodied_kg)):
        _nonnegative(value, name)
    for name, value in (("model_energy_reduction", model_energy_reduction),
                        ("machine_energy_reduction", machine_energy_reduction)):
        if not isfinite(value) or value <= 0:
            raise ValueError(f"{name} must be finite and positive")
    if any(not isfinite(v) or v < 1 for v in (baseline_pue, target_pue)):
        raise ValueError("PUE values must be finite and at least one")
    base = baseline_it_kwh * baseline_pue * baseline_grid_kg_per_kwh
    after_model = base / model_energy_reduction
    after_machine = after_model / machine_energy_reduction
    after_mechanization = after_machine * target_pue / baseline_pue
    target_it = baseline_it_kwh / model_energy_reduction / machine_energy_reduction
    target_operational = target_it * target_pue * target_grid_kg_per_kwh
    baseline_total = base + baseline_embodied_kg
    target_total = target_operational + target_embodied_kg
    return {"baseline_operational_kg": base, "after_model_kg": after_model,
            "after_machine_kg": after_machine, "after_mechanization_kg": after_mechanization,
            "target_it_kwh": target_it, "target_facility_kwh": target_it * target_pue,
            "target_operational_kg": target_operational,
            "baseline_total_kg": baseline_total, "target_total_kg": target_total,
            "operational_reduction": None if target_operational == 0 else base / target_operational,
            "total_reduction": None if target_total == 0 else baseline_total / target_total}
