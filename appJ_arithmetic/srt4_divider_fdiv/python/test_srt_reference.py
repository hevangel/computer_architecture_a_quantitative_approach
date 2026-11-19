import random
import unittest
from fractions import Fraction
from srt_reference import FAULT_COLUMNS, divide_trace, select_digit

class SrtTests(unittest.TestCase):
    def test_only_five_selection_cells_change(self):
        changes = [(row, col)
                   for col in range(16, 32) for row in range(-64, 64)
                   if selected(row, col, False) != selected(row, col, True)]
        self.assertEqual(changes, [(4*(col+1)//3-1, col) for col in FAULT_COLUMNS])

    def test_historic_pair_reaches_deleted_cell(self):
        a,b = 4195835,3145727
        precise, good = divide_trace(a,b)
        faulty, bad = divide_trace(a,b,fault=True)
        self.assertEqual((good[8].row, good[8].column, good[8].digit, bad[8].digit), (31,23,2,0))
        self.assertLess(abs(precise-Fraction(a,b)),Fraction(1,1<<60))
        self.assertGreater(abs(faulty-Fraction(a,b)),Fraction(1,100000))

    def test_correct_remainder_bound_and_quotient(self):
        rng = random.Random(764)
        values = [1,2,3,0x7fffffff,0x80000000,0xffffffff]
        pairs = [(a,b) for a in values for b in values]
        pairs += [(rng.randrange(1,1<<32), rng.randrange(1,1<<32)) for _ in range(2000)]
        for numerator, denominator in pairs:
            approx, steps = divide_trace(numerator,denominator)
            d = denominator << (32-denominator.bit_length())
            self.assertTrue(all(3*abs(step.remainder)<=8*d for step in steps),(numerator,denominator))
            bound=Fraction(2)**(numerator.bit_length()-denominator.bit_length()-64)
            self.assertLessEqual(abs(approx-Fraction(numerator,denominator)),bound)

def selected(row, col, fault):
    try: return select_digit(row,col,fault)
    except ArithmeticError: return None

if __name__ == '__main__':
    unittest.main()
