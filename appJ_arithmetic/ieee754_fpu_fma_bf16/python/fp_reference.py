"""Bit-exact binary32 arithmetic oracle based on rational integers.

Rounding is after the operation; no host floating-point arithmetic is used.
NaNs are canonicalized and tininess is detected after rounding. This is a
reference for future hardware, not a timing or implementation model.
"""
from dataclasses import dataclass
from fractions import Fraction

NV, DZ, OF, UF, NX = 16, 8, 4, 2, 1
QNAN = 0x7fc00000
MODES = ('RNE', 'RTZ', 'RUP', 'RDN')

@dataclass(frozen=True)
class Value:
    kind: str
    sign: int
    value: Fraction = Fraction(0)
    signaling: bool = False

@dataclass(frozen=True)
class Result:
    bits: int
    flags: int = 0

def pow2(e):
    return Fraction(1 << e) if e >= 0 else Fraction(1, 1 << -e)

def decode(bits):
    if not isinstance(bits, int) or not 0 <= bits <= 0xffffffff:
        raise ValueError('binary32 encoding must be a 32-bit integer')
    sign, exp, frac = bits >> 31, (bits >> 23) & 0xff, bits & 0x7fffff
    if exp == 255:
        return Value('nan', sign, signaling=not bool(frac & 0x400000)) if frac else Value('inf', sign)
    if exp == 0:
        magnitude = Fraction(frac) * pow2(-149)
    else:
        magnitude = Fraction((1 << 23) | frac) * pow2(exp - 150)
    return Value('finite', sign, -magnitude if sign else magnitude)

def _round_positive(x, mode, sign):
    q, remainder = divmod(x.numerator, x.denominator)
    if not remainder:
        return q, False
    if mode == 'RNE':
        twice = 2 * remainder
        increment = twice > x.denominator or (twice == x.denominator and bool(q & 1))
    elif mode == 'RTZ':
        increment = False
    elif mode == 'RUP':
        increment = not sign
    else:
        increment = bool(sign)
    return q + int(increment), True

def _floor_log2(x):
    e = x.numerator.bit_length() - x.denominator.bit_length()
    return e - 1 if x < pow2(e) else e

def round32(value, mode='RNE', zero_sign=0):
    if mode not in MODES:
        raise ValueError('unsupported rounding mode')
    x = Fraction(value)
    if not x:
        return Result((int(bool(zero_sign))) << 31)
    sign = int(x < 0)
    x = abs(x)
    exponent = _floor_log2(x)
    if exponent < -126:
        significand, inexact = _round_positive(x / pow2(-149), mode, sign)
        if significand >= 1 << 23:  # rounding reaches the smallest normal
            return Result((sign << 31) | (1 << 23), NX if inexact else 0)
        flags = (UF | NX) if inexact else 0
        return Result((sign << 31) | significand, flags)
    significand, inexact = _round_positive(x / pow2(exponent - 23), mode, sign)
    if significand == 1 << 24:
        significand >>= 1
        exponent += 1
    if exponent > 127:
        to_inf = mode == 'RNE' or (mode == 'RUP' and not sign) or (mode == 'RDN' and sign)
        return Result((sign << 31) | (0x7f800000 if to_inf else 0x7f7fffff), OF | NX)
    return Result((sign << 31) | ((exponent + 127) << 23) | (significand & 0x7fffff), NX if inexact else 0)

def _nan_result(values, invalid=False):
    return Result(QNAN, NV if invalid or any(v.signaling for v in values if v.kind == 'nan') else 0)

def add(a, b, mode='RNE'):
    if mode not in MODES: raise ValueError('unsupported rounding mode')
    x, y = decode(a), decode(b)
    if x.kind == 'nan' or y.kind == 'nan': return _nan_result((x,y))
    if x.kind == y.kind == 'inf' and x.sign != y.sign: return _nan_result((x,y), True)
    if x.kind == 'inf': return Result((x.sign << 31) | 0x7f800000)
    if y.kind == 'inf': return Result((y.sign << 31) | 0x7f800000)
    total = x.value + y.value
    # Same-sign zero operands preserve their sign; exact cancellation is -0 only in RDN.
    sign = x.sign if not x.value and not y.value and x.sign == y.sign else int(mode == 'RDN')
    return round32(total, mode, sign)

def multiply(a, b, mode='RNE'):
    if mode not in MODES: raise ValueError('unsupported rounding mode')
    x, y = decode(a), decode(b)
    if x.kind == 'nan' or y.kind == 'nan': return _nan_result((x,y))
    sign = x.sign ^ y.sign
    if (x.kind == 'inf' and y.kind == 'finite' and not y.value) or (y.kind == 'inf' and x.kind == 'finite' and not x.value):
        return _nan_result((x,y), True)
    if x.kind == 'inf' or y.kind == 'inf': return Result((sign << 31) | 0x7f800000)
    return round32(x.value * y.value, mode, sign)

def _fma_values(x, y, z, mode):
    invalid_product = (x.kind == 'inf' and y.kind == 'finite' and not y.value) or (y.kind == 'inf' and x.kind == 'finite' and not x.value)
    if any(v.kind == 'nan' for v in (x,y,z)):
        return _nan_result((x,y,z), invalid_product)
    if invalid_product: return _nan_result((x,y,z), True)
    product_sign = x.sign ^ y.sign
    if x.kind == 'inf' or y.kind == 'inf':
        if z.kind == 'inf' and z.sign != product_sign: return _nan_result((x,y,z), True)
        return Result((product_sign << 31) | 0x7f800000)
    if z.kind == 'inf': return Result((z.sign << 31) | 0x7f800000)
    product = x.value * y.value
    total = product + z.value
    sign = product_sign if not product and not z.value and product_sign == z.sign else int(mode == 'RDN')
    return round32(total, mode, sign)

def fma(a, b, c, mode='RNE'):
    if mode not in MODES: raise ValueError('unsupported rounding mode')
    return _fma_values(decode(a), decode(b), decode(c), mode)

def bf16_to_fp32(bits):
    if not isinstance(bits, int) or not 0 <= bits < 1 << 16:
        raise ValueError('bf16 encoding must be 16 bits')
    return bits << 16

def fp8_e5m2_to_fp32(bits):
    """Expand IEEE-like E5M2: bias 15, infinities and NaNs supported."""
    if not isinstance(bits, int) or not 0 <= bits < 256: raise ValueError('fp8 encoding must be 8 bits')
    sign, exp, frac = bits >> 7, (bits >> 2) & 31, bits & 3
    if exp == 31:
        return (sign << 31) | 0x7f800000 | (frac << 21)
    if exp == 0 and frac == 0: return sign << 31
    value = Fraction(frac if exp == 0 else 4 + frac) * pow2(-16 if exp == 0 else exp - 17)
    return round32(-value if sign else value).bits


def fp8_e4m3fn_to_fp32(bits):
    """Expand E4M3FN (bias 7, finite-only, all-ones fraction is NaN)."""
    if not isinstance(bits, int) or not 0 <= bits < 256: raise ValueError('fp8 encoding must be 8 bits')
    sign, exp, frac = bits >> 7, (bits >> 3) & 15, bits & 7
    if exp == 15 and frac == 7: return (sign << 31) | QNAN
    if exp == 0 and frac == 0: return sign << 31
    value = Fraction(frac if exp == 0 else 8 + frac) * pow2(-9 if exp == 0 else exp - 10)
    return round32(-value if sign else value).bits

def fma_low_precision(a, b, c, fmt, scale_a=0, scale_b=0, mode='RNE'):
    """Exact power-of-two input scaling followed by one binary32 rounding.

    The scale exponents apply before the product; finite values do not undergo
    an intermediate binary32 rounding. c is a binary32 encoding.
    """
    if mode not in MODES: raise ValueError('unsupported rounding mode')
    if not isinstance(scale_a,int) or not isinstance(scale_b,int) or not -1024 <= scale_a <= 1024 or not -1024 <= scale_b <= 1024:
        raise ValueError('scale exponents must be integers in [-1024, 1024]')
    converters = {'bf16':bf16_to_fp32, 'e5m2':fp8_e5m2_to_fp32, 'e4m3fn':fp8_e4m3fn_to_fp32}
    if fmt not in converters: raise ValueError('unsupported low-precision format')
    x,y = decode(converters[fmt](a)), decode(converters[fmt](b))
    if x.kind == 'finite': x = Value('finite', x.sign, x.value * pow2(scale_a))
    if y.kind == 'finite': y = Value('finite', y.sign, y.value * pow2(scale_b))
    return _fma_values(x,y,decode(c),mode)
