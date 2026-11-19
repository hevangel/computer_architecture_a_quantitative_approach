"""Reference for banked vector memory and strip-mining experiments.

This abstract, sequentially consistent model gives each of eight single-port
banks one operation per cycle. It is an oracle for planned RTL, not RTL itself.
"""

from collections import deque
from math import ceil


def strip_lengths(length, max_vector_length):
    """Partition an arbitrary nonnegative length into bounded vector lengths."""
    if any(isinstance(v, bool) or not isinstance(v, int) for v in (length, max_vector_length)):
        raise ValueError("lengths must be integers")
    if length < 0 or max_vector_length <= 0:
        raise ValueError("length must be nonnegative and MVL positive")
    return [min(max_vector_length, length - start)
            for start in range(0, length, max_vector_length)]


def vector_memory(memory, addresses, *, stores=None, banks=8, mvl=16, startup_cycles=0):
    """Run one vector of indexed loads or stores, strip-mined at mvl.

    memory is a sequence of words, addressed by integer word index. Each strip
    queues lanes in increasing element order to bank address % banks; each bank
    services at most one request/cycle, earliest lane first. There is a barrier
    between strips. Store aliases therefore resolve in increasing element order.
    `stores=None` loads; otherwise it supplies one value per address. Return a
    copy of memory, loaded values in element order (empty for stores), and
    service/ideal/stall counts plus a per-cycle lane trace. No caches, bank
    recovery delay, pipeline startup overlap, exceptions, or bandwidth beyond
    the stated single-port banks are modeled. Input data is never mutated.
    """
    initial = list(memory)
    addr = list(addresses)
    values = None if stores is None else list(stores)
    if isinstance(banks, bool) or not isinstance(banks, int) or banks < 1:
        raise ValueError("banks must be a positive integer")
    if isinstance(startup_cycles, bool) or not isinstance(startup_cycles, int) or startup_cycles < 0:
        raise ValueError("startup cycles must be nonnegative")
    chunks = strip_lengths(len(addr), mvl)
    if values is not None and len(values) != len(addr):
        raise ValueError("one store value per address is required")
    if any(isinstance(a, bool) or not isinstance(a, int) or not 0 <= a < len(initial) for a in addr):
        raise ValueError("address outside memory")
    output = [None] * len(addr) if values is None else []
    trace = []
    ideal = 0
    offset = 0
    for count in chunks:
        queues = [deque() for _ in range(banks)]
        for lane in range(offset, offset + count):
            queues[addr[lane] % banks].append(lane)
        ideal += ceil(count / banks)
        while any(queues):
            cycle = tuple(queue.popleft() for queue in queues if queue)
            trace.append(cycle)
            for lane in cycle:
                if values is None:
                    output[lane] = initial[addr[lane]]
                else:
                    initial[addr[lane]] = values[lane]
        offset += count
    service = len(trace)
    return {"memory": initial, "loads": output, "strip_lengths": chunks,
            "service_cycles": service, "ideal_cycles": ideal,
            "bank_stall_cycles": service - ideal,
            "elapsed_cycles": service + startup_cycles * len(chunks), "trace": trace}


def asymptotic_metrics(banks, startup_cycles, service_cycles, elements):
    """R-infinity and N-half for a measured fixed service rate plus startup.

    N-half is the real-valued intersection for R(n)=n/(startup+n/R_inf);
    real machines have discrete lanes and a rate that depends on access pattern.
    """
    if any(isinstance(v, bool) or not isinstance(v, int) for v in
           (banks, startup_cycles, service_cycles, elements)):
        raise ValueError("arguments must be integers")
    if banks <= 0 or startup_cycles < 0 or service_cycles <= 0 or elements <= 0:
        raise ValueError("invalid counts")
    rate = elements / service_cycles
    if rate > banks:
        raise ValueError("rate cannot exceed bank count")
    return {"r_infinity": rate, "n_half": startup_cycles * rate}
