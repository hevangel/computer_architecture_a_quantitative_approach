"""Exact-integer radix-4 digit trace and five-cell FDIV fault model.

Table addresses follow Edelman, SIAM Review 39(1), 1997, §4, Fig. 4.1.
Outside the five documented columns the selector uses an admissible digit,
rather than trying to recover the historical logic's undocumented tie breaks.
"""
from dataclasses import dataclass
from fractions import Fraction

FRACTION_BITS = 31
WORD_BITS = FRACTION_BITS + 4
WORD_MASK = (1 << WORD_BITS) - 1
FAULT_COLUMNS = (17, 20, 23, 26, 29)

def signed(word, width):
    half = 1 << (width - 1)
    return (word + half) % (half << 1) - half

def select_digit(row, column, fault=False):
    """Select from a divisor column in sixteenths and a row in eighths."""
    high_d = column + 1
    low_p, high_p = 6 * row, 6 * (row + 2)

    def admissible(digit):
        low = max((3 * digit - 2) * column, (3 * digit - 2) * high_d)
        high = min((3 * digit + 2) * column, (3 * digit + 2) * high_d)
        return (digit == -2 or low_p >= low) and (digit == 2 or high_p <= high)

    if column in FAULT_COLUMNS:
        hole = 4 * high_d // 3 - 1
        if fault and row == hole:
            return 0
        maxima = (-2 - 2 * high_d // 3, (-12 - high_d) // 6,
                  (high_d - 6) // 6, -1 + 2 * high_d // 3)
        preferred = next((digit for digit, limit in zip(range(-2, 2), maxima)
                          if row <= limit), 2)
        if admissible(preferred):
            return preferred

    # The real remainder lies in [row/8, (row+2)/8), because the
    # sum and carry were truncated separately. Work in units of 1/48.
    for digit in (0, -1, 1, -2, 2):
        if admissible(digit):
            return digit
    raise ArithmeticError('no valid digit for the selected cell')

@dataclass(frozen=True)
class Step:
    row: int
    column: int
    digit: int
    remainder: int

def divide_trace(numerator, denominator, rounds=33, fault=False):
    if not 0 < numerator < 1 << 32 or not 0 < denominator < 1 << 32 or rounds < 1:
        raise ValueError('expected positive 32-bit operands and at least one round')
    sum_word = numerator << (32 - numerator.bit_length())
    divisor = denominator << (32 - denominator.bit_length())
    exponent = numerator.bit_length() - denominator.bit_length()
    column = divisor >> (FRACTION_BITS - 4)
    carry_word = 0
    acc = 0
    steps = []
    for _ in range(rounds):
        row = signed((signed(sum_word, WORD_BITS) >> (FRACTION_BITS - 3)) +
                     (signed(carry_word, WORD_BITS) >> (FRACTION_BITS - 3)), 7)
        digit = select_digit(row, column, fault)
        # Form a one's complement for a negative addend, then inject
        # its low correction bit into the carry word before scaling.
        subtract = int(digit > 0)
        term = (-digit * divisor - subtract) & WORD_MASK
        new_sum = sum_word ^ carry_word ^ term
        new_carry = ((sum_word & carry_word) | (sum_word & term) |
                     (carry_word & term)) << 1
        sum_word = (new_sum << 2) & WORD_MASK
        carry_word = ((new_carry | subtract) << 2) & WORD_MASK
        acc = 4 * acc + digit
        steps.append(Step(row, column, digit, signed(sum_word + carry_word, WORD_BITS)))
    quotient = Fraction(acc, 4 ** (rounds - 1)) * Fraction(2) ** exponent
    return quotient, tuple(steps)
