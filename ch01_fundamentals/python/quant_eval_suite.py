"""Idealized quantitative architecture models with explicit units.

Areas are in mm², defect densities in defects/mm², costs in a common currency,
time in hours unless otherwise specified, and voltages/frequencies in SI units.
"""

from math import exp, fsum, isfinite, log, pi, sqrt


def _positive(x, name):
    if not isfinite(x) or x <= 0:
        raise ValueError(f"{name} must be finite and positive")
    return x


def _nonnegative(x, name):
    if not isfinite(x) or x < 0:
        raise ValueError(f"{name} must be finite and nonnegative")
    return x


def dies_per_wafer(wafer_diameter_mm, die_area_mm2):
    """Approximate gross dies per wafer, including a circular-edge correction.

    This continuous approximation is not a geometric packing algorithm and must
    not be used when it predicts fewer than one die.
    """
    diameter = _positive(wafer_diameter_mm, "wafer_diameter_mm")
    area = _positive(die_area_mm2, "die_area_mm2")
    count = pi * diameter ** 2 / (4 * area) - pi * diameter / sqrt(2 * area)
    if count < 1:
        raise ValueError("approximation gives fewer than one gross die")
    return count


def die_yield(die_area_mm2, defect_density_per_mm2, clustering=3.0, wafer_yield=1.0):
    """Clustered-defect yield: wafer_yield * (1 + density*area/alpha)^(-alpha)."""
    _positive(die_area_mm2, "die_area_mm2")
    _nonnegative(defect_density_per_mm2, "defect_density_per_mm2")
    _positive(clustering, "clustering")
    if not isfinite(wafer_yield) or not 0 < wafer_yield <= 1:
        raise ValueError("wafer_yield must be in (0, 1]")
    return wafer_yield * (1 + defect_density_per_mm2 * die_area_mm2 / clustering) ** -clustering


def good_die_cost(wafer_cost, wafer_diameter_mm, die_area_mm2, defect_density_per_mm2,
                  clustering=3.0, wafer_yield=1.0):
    """Wafer cost divided by expected good dies; excludes test and packaging."""
    _nonnegative(wafer_cost, "wafer_cost")
    return wafer_cost / (dies_per_wafer(wafer_diameter_mm, die_area_mm2) *
                         die_yield(die_area_mm2, defect_density_per_mm2, clustering, wafer_yield))


def package_cost(die_costs, assembly_cost, assembly_yield):
    """Expected cost of a good assembly from independently known-good dies.

    Each attempt consumes one of each die and incurs assembly_cost, including
    attempts which fail assembly. Die testing, interposer and package costs must
    be included by the caller in die_costs or assembly_cost.
    """
    costs = list(die_costs)
    if not costs:
        raise ValueError("at least one die is required")
    for cost in costs:
        _nonnegative(cost, "die cost")
    _nonnegative(assembly_cost, "assembly_cost")
    if not isfinite(assembly_yield) or not 0 < assembly_yield <= 1:
        raise ValueError("assembly_yield must be in (0, 1]")
    return (fsum(costs) + assembly_cost) / assembly_yield


def fit_to_mttf(failures_per_billion_hours):
    """Convert FIT to mean time to failure in hours."""
    return 1e9 / _positive(failures_per_billion_hours, "FIT")


def series_mttf(component_mttfs):
    """MTTF of independent exponential components in a fail-any series system."""
    times = list(component_mttfs)
    if not times:
        raise ValueError("at least one component is required")
    return 1 / fsum(1 / _positive(t, "component MTTF") for t in times)


def parallel_two_mttf(first_mttf, second_mttf):
    """MTTF of two independent exponential components without repair.

    The system fails when both fail; repairs and common-cause faults are absent.
    """
    first = _positive(first_mttf, "first_mttf")
    second = _positive(second_mttf, "second_mttf")
    return first + second - 1 / (1 / first + 1 / second)


def availability(mttf, mttr):
    """Steady-state availability of a repairable component, MTTF/(MTTF+MTTR)."""
    return _positive(mttf, "mttf") / (mttf + _nonnegative(mttr, "mttr"))


def parallel_availability(component_availabilities):
    """Availability of independent components when any working unit suffices."""
    values = list(component_availabilities)
    if not values or any(not isfinite(a) or not 0 <= a <= 1 for a in values):
        raise ValueError("provide component availabilities in [0, 1]")
    unavailable = 1.0
    for a in values:
        unavailable *= 1 - a
    return 1 - unavailable


def dvfs(capacitance_f, activity, voltage_v, frequency_hz, cycles, leakage_w=0):
    """Return dynamic W, total J, delay s, and energy-delay product J*s.

    Uses dynamic P = activity*C*V²*f and a constant leakage power; activity
    incorporates the chosen switching convention. Work is a fixed cycle count.
    """
    _nonnegative(capacitance_f, "capacitance_f")
    if not isfinite(activity) or not 0 <= activity <= 1:
        raise ValueError("activity must be in [0, 1]")
    _positive(voltage_v, "voltage_v")
    _positive(frequency_hz, "frequency_hz")
    _nonnegative(cycles, "cycles")
    _nonnegative(leakage_w, "leakage_w")
    dynamic = activity * capacitance_f * voltage_v ** 2 * frequency_hz
    delay = cycles / frequency_hz
    energy = (dynamic + leakage_w) * delay
    return dynamic, energy, delay, energy * delay


def carbon_kg(energy_kwh, grid_kg_per_kwh, embodied_kg):
    """Return operational and total emissions in kg CO2e."""
    operational = _nonnegative(energy_kwh, "energy_kwh") * _nonnegative(grid_kg_per_kwh, "grid_kg_per_kwh")
    return operational, operational + _nonnegative(embodied_kg, "embodied_kg")


def benchmark_summary(values, weights=None):
    """Return arithmetic, weighted arithmetic, harmonic and geometric means,
    plus population geometric standard deviation for positive benchmark values.
    """
    samples = list(values)
    if not samples:
        raise ValueError("at least one value is required")
    for value in samples:
        _positive(value, "benchmark value")
    w = [1.0] * len(samples) if weights is None else list(weights)
    if len(w) != len(samples):
        raise ValueError("weights and values must have equal lengths")
    for weight in w:
        _nonnegative(weight, "weight")
    total = fsum(w)
    if total <= 0:
        raise ValueError("at least one weight must be positive")
    logs = [log(value) for value in samples]
    mean_log = fsum(logs) / len(samples)
    return {
        "arithmetic": fsum(samples) / len(samples),
        "weighted_arithmetic": fsum(x * weight for x, weight in zip(samples, w)) / total,
        "harmonic": len(samples) / fsum(1 / x for x in samples),
        "geometric": exp(mean_log),
        "geometric_stddev": exp(sqrt(fsum((x - mean_log) ** 2 for x in logs) / len(logs))),
    }
