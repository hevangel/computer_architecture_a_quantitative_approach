import itertools
import random
import unittest

import raid6_chipkill_ref as ref


class Raid6ReferenceTests(unittest.TestCase):
    def test_field_arithmetic_against_polynomial_long_division(self):
        # Separately multiply polynomials then reduce the high terms.
        for width, polynomial in ((4, 0x13), (8, 0x11d)):
            for a in range(1 << width):
                for b in range(1 << width):
                    product = 0
                    for bit in range(width):
                        if b & (1 << bit):
                            product ^= a << bit
                    for bit in range(2 * width - 2, width - 1, -1):
                        if product & (1 << bit):
                            product ^= polynomial << (bit - width)
                    self.assertEqual(ref.gf_mul(a, b, width, polynomial), product)

    def test_every_single_and_double_disk_erasure(self):
        rng = random.Random(44)
        for data in ([0, 0, 0, 0], [1, 2, 4, 8], [255, 128, 1, 17],
                     *([rng.randrange(256) for _ in range(4)] for _ in range(32))):
            stripe = ref.encode(data, 8, 0x11d)
            for count in (1, 2):
                for missing in itertools.combinations(range(6), count):
                    damaged = [0 if i in missing else x for i, x in enumerate(stripe)]
                    self.assertEqual(ref.recover_erasures(damaged, missing), stripe)

    def test_every_symbol_position_and_nonzero_error(self):
        for data in ([0] * 8, list(range(8)), [15] * 8):
            stripe = ref.encode(data, 4, 0x13)
            self.assertEqual(ref.correct_single_symbol(stripe), (stripe, None))
            for position in range(10):
                for error in range(1, 16):
                    damaged = stripe.copy()
                    damaged[position] ^= error
                    self.assertEqual(ref.correct_single_symbol(damaged), (stripe, position))

    def test_invalid_inputs(self):
        for action in (lambda: ref.gf_div(1, 0, 4, 0x13),
                       lambda: ref.encode([16], 4, 0x13),
                       lambda: ref.recover_erasures([0] * 6, [0, 1, 2]),
                       lambda: ref.correct_single_symbol([0] * 9)):
            with self.assertRaises(ValueError):
                action()


if __name__ == '__main__':
    unittest.main()
