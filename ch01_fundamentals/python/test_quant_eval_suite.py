import math
import unittest

import quant_eval_suite as q


class QuantitativeTests(unittest.TestCase):
    def test_wafer_yield_and_packaging(self):
        self.assertAlmostEqual(q.dies_per_wafer(300, 100), math.pi * 225 - math.pi * 300 / math.sqrt(200))
        self.assertAlmostEqual(q.die_yield(100, 0.003, 3, 0.9), 0.9 / 1.1 ** 3)
        self.assertAlmostEqual(q.package_cost([10, 20, 30, 40], 8, 0.9), 120)
        # Different die areas and packaging overhead create a genuine crossover.
        def cost(density):
            mono = q.package_cost([q.good_die_cost(10000, 300, 400, density)], 10, 0.95)
            chiplets = q.package_cost([q.good_die_cost(10000, 300, 110, density)] * 4, 100, 0.9)
            return mono, chiplets
        self.assertLess(*cost(0.0001))
        mono, chiplets = cost(0.005)
        self.assertGreater(mono, chiplets)

    def test_reliability_and_availability(self):
        self.assertEqual(q.fit_to_mttf(100), 10000000)
        self.assertAlmostEqual(q.series_mttf([100, 100]), 50)
        self.assertAlmostEqual(q.parallel_two_mttf(100, 100), 150)
        self.assertAlmostEqual(q.parallel_two_mttf(100, 200), 700 / 3)
        self.assertAlmostEqual(q.availability(99, 1), 0.99)
        self.assertAlmostEqual(q.parallel_availability([0.99, 0.99]), 0.9999)

    def test_dvfs_and_carbon(self):
        fast = q.dvfs(1e-9, 0.5, 1, 1e9, 1e9)
        slow = q.dvfs(1e-9, 0.5, 0.5, 0.5e9, 1e9)
        self.assertAlmostEqual(slow[0] / fast[0], 1 / 8)
        self.assertAlmostEqual(slow[1] / fast[1], 1 / 4)
        self.assertAlmostEqual(slow[3] / fast[3], 1 / 2)
        self.assertEqual(q.carbon_kg(100, 0.5, 20), (50, 70))

    def test_means_and_weight_normalization(self):
        values = q.benchmark_summary([1, 4], [1, 3])
        self.assertAlmostEqual(values["arithmetic"], 2.5)
        self.assertAlmostEqual(values["weighted_arithmetic"], 3.25)
        self.assertAlmostEqual(values["harmonic"], 1.6)
        self.assertAlmostEqual(values["geometric"], 2)
        self.assertAlmostEqual(values["geometric_stddev"], 2)
        self.assertEqual(values, q.benchmark_summary([1, 4], [2, 6]))

    def test_invalid_inputs(self):
        for call in (lambda: q.dies_per_wafer(1, 1000), lambda: q.die_yield(100, -1),
                     lambda: q.package_cost([], 1, 1), lambda: q.parallel_two_mttf(0, 1),
                     lambda: q.parallel_availability([1.1]), lambda: q.dvfs(1, 2, 1, 1, 1),
                     lambda: q.benchmark_summary([0, 1]), lambda: q.benchmark_summary([1], [0])):
            with self.assertRaises(ValueError):
                call()


if __name__ == "__main__":
    unittest.main()
