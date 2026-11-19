import math
from decimal import Decimal, localcontext
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




class ChipletBreakEvenTests(unittest.TestCase):
    def setUp(self):
        self.params = dict(wafer_cost=10000, wafer_diameter_mm=300,
                           monolithic_area_mm2=400, chiplet_area_mm2=110,
                           chiplet_count=4, monolithic_assembly_cost=10,
                           monolithic_assembly_yield=0.95, chiplet_assembly_cost=100,
                           chiplet_assembly_yield=0.9, density_low=0, density_high=0.005)
    def test_independent_high_precision_crossing(self):
        # Derive the synthetic crossing independently using 55-digit decimal arithmetic.
        with localcontext() as context:
            context.prec = 55
            D = Decimal
            pi = D("3.14159265358979323846264338327950288419716939937510582")
            def die_cost(area, defects):
                dies = pi * D(300)**2 / (4 * area) - pi * 300 / (2 * area).sqrt()
                return D(10000) / dies * (1 + defects * area / 3)**3
            def difference(defects):
                return ((die_cost(D(400), defects) + 10) / D(".95") -
                        (4 * die_cost(D(110), defects) + 100) / D(".9"))
            low, high = D(0), D(".005")
            for _ in range(180):
                mid = (low + high) / 2
                if difference(mid) < 0:
                    low = mid
                else:
                    high = mid
            reference = float((low + high) / 2)
        density = q.chiplet_break_even_density(**self.params, density_tolerance=1e-15)
        self.assertAlmostEqual(reference, 0.0030865802136994683, delta=1e-18)
        self.assertAlmostEqual(density, reference, delta=5e-16)
        chiplet_cost = q.uniform_chiplet_cost(10000, 300, 110, 4, density, 100, 0.9)
        mono_cost = q.package_cost([q.good_die_cost(10000, 300, 400, density)], 10, 0.95)
        self.assertAlmostEqual(chiplet_cost, 216.98437375443226, places=9)
        self.assertAlmostEqual(chiplet_cost, mono_cost, places=9)
        self.assertLess(q.package_cost([q.good_die_cost(10000, 300, 400, density-0.0001)], 10, 0.95),
                        q.uniform_chiplet_cost(10000, 300, 110, 4, density-0.0001, 100, 0.9))
        self.assertGreater(q.package_cost([q.good_die_cost(10000, 300, 400, density+0.0001)], 10, 0.95),
                           q.uniform_chiplet_cost(10000, 300, 110, 4, density+0.0001, 100, 0.9))
    def test_validation_and_no_crossing(self):
        for overrides in (dict(density_low=-1), dict(density_low=0.005),
                          dict(density_high=0.00001), dict(density_tolerance=0),
                          dict(chiplet_count=0), dict(chiplet_count=True),
                          dict(max_iterations=1)):
            with self.subTest(overrides=overrides), self.assertRaises(ValueError):
                q.chiplet_break_even_density(**(self.params | overrides))
        with self.assertRaises(ValueError):
            q.chiplet_break_even_density(**(self.params | dict(wafer_cost=0,
                monolithic_assembly_cost=0, chiplet_assembly_cost=0)))
class RepairableRedundancyTests(unittest.TestCase):
    def test_power_supply_example_and_exact_first_step_solution(self):
        # 6th ed. §1.7, pp. 39–40: 200,000 h component MTTF and 24 h repair.
        # The book uses a rare-failure approximation (~830 million h, ~4150x).
        # Exact exponential first-passage calculation includes time in both states.
        result = q.redundant_pair_repair_mttf(200000, 24)
        self.assertAlmostEqual(result, 833633333.3333334)
        self.assertAlmostEqual(result / 200000, 4168.166666666667)
        self.assertAlmostEqual(result / 200000, 4150, delta=19)
        self.assertAlmostEqual(result / (200000**2 / (2 * 24)), 1.00036)

    def test_limits_and_validation(self):
        # Very slow repair approaches the no-repair pair's 1.5-component MTTF.
        self.assertAlmostEqual(q.redundant_pair_repair_mttf(10, 1e12), 15, places=9)
        for mttf, mttr in ((0, 1), (1, 0), (-1, 1), (1, float("inf"))):
            with self.subTest(mttf=mttf, mttr=mttr), self.assertRaises(ValueError):
                q.redundant_pair_repair_mttf(mttf, mttr)

if __name__ == "__main__":
    unittest.main()
