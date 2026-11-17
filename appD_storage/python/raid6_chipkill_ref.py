"""Independent erasure and symbol-code reference for the planned RTL example.

RAID uses four byte data symbols and two parities over GF(2^8), polynomial
0x11d, coefficients 1, 2, 4, 8. The symbol code uses eight data nibbles and
P/Q nibbles over GF(2^4), polynomial 0x13, coefficients powers of 2. This
educational code locates a single symbol corruption; it is not JEDEC Chipkill.
"""


def gf_mul(a, b, width, polynomial):
    """Multiply polynomial-basis field elements using shift and reduction."""
    if width not in (4, 8):
        raise ValueError("supported field widths are four and eight")
    if any(isinstance(v, bool) or not isinstance(v, int) or not 0 <= v < 1 << width
           for v in (a, b)):
        raise ValueError("field element out of range")
    result = 0
    for _ in range(width):
        if b & 1:
            result ^= a
        b >>= 1
        a <<= 1
        if a & (1 << width):
            a ^= polynomial
    return result


def gf_div(a, b, width, polynomial):
    """Divide using Fermat inversion, independent of a lookup table."""
    if b == 0:
        raise ValueError("division by zero")
    power, factor, exponent = 1, b, (1 << width) - 2
    while exponent:
        if exponent & 1:
            power = gf_mul(power, factor, width, polynomial)
        factor = gf_mul(factor, factor, width, polynomial)
        exponent >>= 1
    return gf_mul(a, power, width, polynomial)


def encode(data, width, polynomial):
    """Return data followed by XOR P and weighted Q parity symbols."""
    data = list(data)
    if not data or len(data) > (1 << width) - 1:
        raise ValueError("invalid number of data symbols")
    p = q = 0
    coefficient = 1
    for value in data:
        # Validate even when coefficient multiplication would mask the value.
        q ^= gf_mul(value, coefficient, width, polynomial)
        p ^= value
        coefficient = gf_mul(coefficient, 2, width, polynomial)
    return data + [p, q]


def recover_erasures(stripe, missing, width=8, polynomial=0x11d):
    """Recover up to two known erasures, including parity erasures.

    Input stripe has data, P, Q in that order. Missing values are ignored.
    Surviving symbols must be valid and consistent; no error detection is
    promised for additional corrupt survivors.
    """
    stripe = list(stripe)
    missing = set(missing)
    n = len(stripe) - 2
    if n < 1 or n > (1 << width) - 1 or len(missing) > 2 or any(
        isinstance(i, bool) or not isinstance(i, int) or not 0 <= i < len(stripe)
        for i in missing
    ):
        raise ValueError("invalid stripe or erasures")
    for i, value in enumerate(stripe):
        if i not in missing:
            gf_mul(value, 1, width, polynomial)
    coefficients = [1]
    for _ in range(1, n):
        coefficients.append(gf_mul(coefficients[-1], 2, width, polynomial))
    data_missing = [i for i in range(n) if i in missing]
    p_known = n not in missing
    q_known = n + 1 not in missing
    p_residual = stripe[n] if p_known else 0
    q_residual = stripe[n + 1] if q_known else 0
    for i in range(n):
        if i not in missing:
            p_residual ^= stripe[i]
            q_residual ^= gf_mul(stripe[i], coefficients[i], width, polynomial)
    if len(data_missing) == 1:
        i = data_missing[0]
        stripe[i] = p_residual if p_known else gf_div(q_residual, coefficients[i], width, polynomial)
    elif len(data_missing) == 2:
        i, j = data_missing
        # P residual = x+y, Q residual = ai*x+aj*y.
        x = gf_div(q_residual ^ gf_mul(coefficients[j], p_residual, width, polynomial),
                   coefficients[i] ^ coefficients[j], width, polynomial)
        stripe[i], stripe[j] = x, p_residual ^ x
    parity = encode(stripe[:n], width, polynomial)
    for i in missing:
        stripe[i] = parity[i]
    return stripe


def correct_single_symbol(stripe):
    """Correct one unknown-position nibble error in an eight-data-symbol word.

    Returns (corrected symbols, position or None). Multiple errors may be
    miscorrected; callers need an outer integrity check to detect that case.
    """
    stripe = list(stripe)
    if len(stripe) != 10:
        raise ValueError("eight data and two check symbols required")
    for value in stripe:
        gf_mul(value, 1, 4, 0x13)
    expected = encode(stripe[:8], 4, 0x13)
    sp, sq = stripe[8] ^ expected[8], stripe[9] ^ expected[9]
    if not sp and not sq:
        return stripe, None
    if not sq:
        position = 8
    elif not sp:
        position = 9
    else:
        coefficient = 1
        position = None
        for i in range(8):
            if gf_mul(sp, coefficient, 4, 0x13) == sq:
                position = i
                break
            coefficient = gf_mul(coefficient, 2, 4, 0x13)
        if position is None:
            raise ValueError("uncorrectable syndrome")
    stripe[position] ^= sq if position == 9 else sp
    return stripe, position
