import unittest

import roofline_loop_model as model


class RooflineLoopTests(unittest.TestCase):
    def test_roofline(self):
        self.assertEqual(model.roofline(100, 10, 2), (10, 20, "memory"))
        self.assertEqual(model.roofline(100, 10, 20), (10, 100, "compute"))
        self.assertEqual(model.roofline(100, 10, 10), (10, 100, "balanced"))
        with self.assertRaises(ValueError):
            model.roofline(100, 0, 1)

    def test_gcd_is_only_necessary_for_bounded_loops(self):
        self.assertFalse(model.gcd_may_alias(2, 0, 2, 1))
        self.assertTrue(model.gcd_may_alias(1, 0, 1, 100))
        self.assertIsNone(model.loop_carried_witness(1, 0, 1, 100, 0, 10))
        self.assertTrue(model.gcd_may_alias(0, 7, 0, 7))
        self.assertFalse(model.gcd_may_alias(0, 7, 0, 8))

    def test_bounded_witness_and_direction(self):
        self.assertEqual(model.loop_carried_witness(1, 0, 1, -1, 0, 5), (0, 1))
        self.assertIsNone(model.loop_carried_witness(1, 0, 1, 0, 0, 5))
        self.assertEqual(model.loop_carried_witness(1, 0, 1, 1, 4, -1, -1), (4, 3))
        self.assertEqual(model.loop_carried_witness(0, 2, 0, 2, 0, 2), (0, 1))
        with self.assertRaises(ValueError):
            model.loop_carried_witness(1, 0, 1, 0, 0, 4, 0)


if __name__ == "__main__":
    unittest.main()
