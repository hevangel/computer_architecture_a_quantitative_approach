"""Independent fixed-point arithmetic checks for the DSP example."""
from fractions import Fraction


def round_even(value):
    return round(Fraction(value, 1 << 15))


def main():
    order = [int(f"{i:04b}"[::-1], 2) for i in range(16)]
    assert order == [0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15]
    addresses = [(13 + i) % 16 for i in range(16)]
    total = sum(index * 2048 * 2048 for index in addresses)
    assert total == 503316480 and round_even(total) == 15360
    assert [round_even(x * 16384) for x in (1, 3, -1, -3)] == [0, 2, 0, -2]
    assert 520 * 32767 * 32767 > (1 << 39) - 1
    assert 520 * -32768 * 32767 < -(1 << 39)
    print("DSP reference checks passed")


if __name__ == '__main__':
    main()
