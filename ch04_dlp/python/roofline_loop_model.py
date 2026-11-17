"""Roofline ceilings and bounded affine dependence checks.

The GCD test is a necessary, not sufficient, condition for bounded loops. The
bounded checker enumerates iterations and reports an actual loop-carried pair.
"""

from dataclasses import dataclass
from itertools import product
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


def affine_nest_may_alias(first_coefficients, first_offset, second_coefficients, second_offset):
    """Necessary GCD test for equality of two affine accesses in a loop nest.

    Each expression has one integer coefficient per loop variable. The two
    iteration vectors are independent here, so this ignores bounds, ordering,
    and whether an access writes; True is not proof of a dependence.
    """
    first = tuple(first_coefficients)
    second = tuple(second_coefficients)
    if not first or len(first) != len(second):
        raise ValueError("coefficient vectors must have equal nonzero length")
    values = first + second + (first_offset, second_offset)
    if any(isinstance(x, bool) or not isinstance(x, int) for x in values):
        raise ValueError("coefficients and offsets must be integers")
    divisor = gcd(*first, *second)
    difference = second_offset - first_offset
    return difference == 0 if divisor == 0 else difference % divisor == 0


def affine_nest_witness(first_coefficients, first_offset, second_coefficients,
                        second_offset, ranges):
    """Find earlier/later iteration vectors accessing the same linear element.

    ranges are Python range objects, outermost first. Order is lexicographic in
    iteration order, including descending ranges. The accesses must refer to the
    same array; the caller must decide whether either access writes. Runtime and
    memory scale with the product of loop trip counts, so use bounded examples.
    """
    first = tuple(first_coefficients)
    second = tuple(second_coefficients)
    dimensions = tuple(ranges)
    may_alias = affine_nest_may_alias(first, first_offset, second, second_offset)
    if len(dimensions) != len(first) or any(not isinstance(r, range) for r in dimensions):
        raise ValueError("one range per coefficient is required")
    if not may_alias:
        return None
    earlier = {}
    for iteration in product(*dimensions):
        target = sum(c * i for c, i in zip(second, iteration)) + second_offset
        if target in earlier:
            return earlier[target], iteration
        address = sum(c * i for c, i in zip(first, iteration)) + first_offset
        earlier.setdefault(address, iteration)
    return None


def kernel_intensity(operations, transferred_bytes):
    """Compute operations per byte transferred at a stated memory boundary.

    The caller supplies actual or assumed transfers, including write traffic.
    This function does not infer cache hits or combine arithmetic operations.
    """
    if not isfinite(operations) or operations < 0:
        raise ValueError("operations must be finite and nonnegative")
    if not isfinite(transferred_bytes) or transferred_bytes <= 0:
        raise ValueError("transferred bytes must be finite and positive")
    return operations / transferred_bytes


def compare_rooflines(targets, operations, transferred_bytes):
    """Compare ideal ceilings for named (peak ops/s, bandwidth bytes/s) targets.

    Assumes the same arithmetic intensity at the relevant memory boundary on
    each target. Actual systems may transfer different bytes and attain less.
    """
    intensity = kernel_intensity(operations, transferred_bytes)
    return {name: roofline(peak, bandwidth, intensity)
            for name, (peak, bandwidth) in targets.items()}


@dataclass(frozen=True)
class AffineAccess:
    """A named read or write of one scalar affine element in an array."""
    name: str
    array: str
    mode: str
    coefficients: tuple[int, ...]
    offset: int = 0


@dataclass(frozen=True)
class DependenceWitness:
    """First observed conflict for an access pair, kind and direction vector."""
    source: str
    target: str
    kind: str
    source_iteration: tuple[int, ...]
    target_iteration: tuple[int, ...]
    distance: tuple[int, ...]
    direction: tuple[str, ...]
    carried: bool


def classify_affine_dependences(accesses, ranges):
    """Enumerate distinct ordered affine conflicts in a bounded rectangular nest.

    Accesses are in execution order within each iteration, outermost loop first.
    Return one actual witness per (source, target, kind, direction, carried),
    ordered by its first discovery. Kinds are flow (write/read), anti (read/write),
    and output (write/write). Read/read pairs do not conflict. Iteration order
    follows each range, including negative steps; distance is target minus source
    in index values, and direction components are '-', '=', or '+'.

    This reports potentially transitive conflicts, not just the last writer.
    Equal array names denote the same storage; callers must express aliasing and
    byte overlap themselves. Rectangular finite ranges and scalar linear element
    addresses only; the history can grow with the number of distinct addresses.
    """
    ops = tuple(accesses)
    dims = tuple(ranges)
    if not dims or any(not isinstance(r, range) for r in dims):
        raise ValueError("ranges must be a nonempty sequence of range objects")
    if not ops or any(not isinstance(a, AffineAccess) for a in ops):
        raise ValueError("accesses must contain AffineAccess values")
    names = set()
    for access in ops:
        if not isinstance(access.name, str) or not access.name or access.name in names:
            raise ValueError("access names must be unique nonempty strings")
        if not isinstance(access.array, str) or not access.array or access.mode not in ("read", "write"):
            raise ValueError("array must be named and mode must be read or write")
        if len(access.coefficients) != len(dims):
            raise ValueError("one coefficient per loop dimension is required")
        affine_nest_may_alias(access.coefficients, access.offset, access.coefficients, access.offset)
        names.add(access.name)

    results = {}
    # For each address and site, retain the first event for every direction
    # relevant to a later target. Retaining all distinct source iterations is
    # necessary: later targets can induce different direction vectors.
    history = {}
    for iteration in product(*dims):
        current = []
        for target_index, target in enumerate(ops):
            address = target.offset + sum(c * i for c, i in zip(target.coefficients, iteration))
            location = (target.array, address)
            previous = history.get(location, ())
            same_iteration = ((source_index, source_iter) for source_index, source_iter, key in current if key == location)
            for source_index, source_iter in (*previous, *same_iteration):
                source = ops[source_index]
                if source.mode == target.mode == "read":
                    continue
                kind = ("flow" if source.mode == "write" and target.mode == "read" else
                        "anti" if source.mode == "read" and target.mode == "write" else "output")
                distance = tuple(b - a for a, b in zip(source_iter, iteration))
                direction = tuple("+" if d > 0 else "-" if d < 0 else "=" for d in distance)
                carried = any(distance)
                key = (source_index, target_index, kind, direction, carried)
                results.setdefault(key, DependenceWitness(source.name, target.name, kind,
                                                          source_iter, iteration, distance, direction, carried))
            current.append((target_index, iteration, location))
        for source_index, source_iter, location in current:
            history.setdefault(location, []).append((source_index, source_iter))
    return tuple(results.values())
