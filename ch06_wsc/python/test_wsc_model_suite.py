import random
import unittest

import wsc_model_suite as wsc


class WarehouseModelsTest(unittest.TestCase):
    def test_cost_power_and_carbon(self):
        self.assertEqual(wsc.pue(120, 100), 1.2)
        self.assertEqual(wsc.energy_cost(100, 1.2, 1000, 0.1), 12000)
        self.assertEqual(wsc.total_cost(500000, 200000, 12000, 5), 760000)
        self.assertEqual(wsc.carbon_kg(120000, 0.4, 2000), 50000)
        self.assertAlmostEqual(wsc.transfer_time(0.01, 1000, 100000), 0.02)

    def test_invalid_inputs(self):
        for call in (lambda: wsc.pue(1, 2), lambda: wsc.pue(1, 0),
                     lambda: wsc.energy_cost(1, 0.9, 1, 1),
                     lambda: wsc.transfer_time(0, 1, 0),
                     lambda: wsc.fanout_latency([1], [1, 2]),
                     lambda: wsc.percentile([], 99)):
            with self.assertRaises(ValueError):
                call()

    def test_fanout_hedge_and_percentile(self):
        self.assertEqual(wsc.fanout_latency([1, 8], [3, 2], 2), 4)
        self.assertEqual(wsc.percentile([5, 1, 3, 4, 2], 80), 4)
        rng = random.Random(2025)
        plain, hedged = [], []
        for _ in range(2000):
            primary = [rng.paretovariate(1.5) for _ in range(8)]
            replica = [rng.paretovariate(1.5) for _ in range(8)]
            plain.append(wsc.fanout_latency(primary))
            hedged.append(wsc.fanout_latency(primary, replica, 2))
        self.assertLess(wsc.percentile(hedged, 99), wsc.percentile(plain, 99))
        self.assertTrue(all(h <= p for h, p in zip(hedged, plain)))

    def test_fifo_replica_scheduling(self):
        requests = [(0, 10, 1), (0, 1, 1)]
        primary = wsc.simulate_replicas(requests)
        hedged = wsc.simulate_replicas(requests, "hedged", 2)
        tied = wsc.simulate_replicas(requests, "tied")
        self.assertEqual(primary, {"response_times": [10, 11], "busy_time": 11,
                                   "replicas_submitted": 2, "replicas_started": 2})
        self.assertEqual(hedged, {"response_times": [3, 4], "busy_time": 6,
                                  "replicas_submitted": 4, "replicas_started": 4})
        self.assertEqual(tied, {"response_times": [10, 1], "busy_time": 11,
                                "replicas_submitted": 4, "replicas_started": 2})

    def test_simultaneous_completion_and_cancellation(self):
        # Completion at the timer deadline suppresses an unnecessary hedge.
        self.assertEqual(wsc.simulate_replicas([(0, 2, 1)], "hedged", 2),
                         {"response_times": [2], "busy_time": 2,
                          "replicas_submitted": 1, "replicas_started": 1})
        # An already-running losing replica consumes time but is cancelled.
        self.assertEqual(wsc.simulate_replicas([(0, 10, 2)], "hedged", 1),
                         {"response_times": [3], "busy_time": 5,
                          "replicas_submitted": 2, "replicas_started": 2})
        self.assertEqual(wsc.simulate_replicas([])["response_times"], [])
        with self.assertRaises(ValueError):
            wsc.simulate_replicas([(0, 0, 1)], "tied")

    def test_queueing_tail_on_seeded_heavy_tail_trace(self):
        rng = random.Random(71)
        requests = [(i * 10, rng.paretovariate(1.5), rng.paretovariate(1.5))
                    for i in range(2000)]
        primary = wsc.simulate_replicas(requests)
        hedged = wsc.simulate_replicas(requests, "hedged", 2)
        self.assertLess(wsc.percentile(hedged["response_times"], 99),
                        wsc.percentile(primary["response_times"], 99))
        self.assertGreater(hedged["replicas_started"], len(requests))

class FleetCostTest(unittest.TestCase):
    def test_utilization_and_annualized_cost(self):
        # 100 servers at 100 W idle and 300 W peak draw 20 kW at 50%.
        self.assertEqual(wsc.server_power_kw(100, 100, 300, 0.5), 20)
        self.assertEqual(wsc.server_power_kw(100, 100, 300, 0), 10)
        self.assertEqual(wsc.server_power_kw(100, 100, 300, 1), 30)
        result = wsc.fleet_tco(100, 3000, 3, 30, 10, 10, 1.2, 0.1,
                               [(4380, 10), (4380, 30)], 5000)
        self.assertEqual(result["it_kwh"], 175200)
        self.assertEqual(result["facility_kwh"], 210240)
        self.assertEqual(result["server_amortization"], 100000)
        self.assertEqual(result["facility_amortization"], 30000)
        self.assertEqual(result["energy_cost"], 21024)
        self.assertEqual(result["annual_total"], 156024)

    def test_capacity_and_period_validation(self):
        args = (100, 3000, 3, 30, 10, 10, 1.2, 0.1)
        for periods in ([], [(8760, 31)], [(8759, 20)], [(-1, 10), (8761, 10)]):
            with self.subTest(periods=periods), self.assertRaises(ValueError):
                wsc.fleet_tco(*args, periods)
        for args in ((True, 100, 300, 0.5), (1, 300, 100, 0.5),
                     (1, 100, 300, 1.01), (1, 100, 300, float("nan"))):
            with self.subTest(args=args), self.assertRaises(ValueError):
                wsc.server_power_kw(*args)


class HierarchyTest(unittest.TestCase):
    def test_sixth_edition_transfer_bottlenecks(self):
        # Sec. 6.3, p. 480: 20 GB/s DRAM and 200 MB/s disk;
        # rack and array links limit either medium to 100 and 10 MB/s.
        size = 1000 * 10**6
        paths = []
        for bandwidth in (20 * 10**9, 200 * 10**6):
            paths.append([wsc.hierarchy_path(0, bandwidth, 16 * 2**30, n, links)
                          for n, links in ((1, ()), (80, ((0, 100 * 10**6),)),
                                           (2400, ((0, 10 * 10**6),)))])
        self.assertEqual([[wsc.transfer_time(p["latency_seconds"], size,
                                             p["bytes_per_second"]) for p in tier]
                          for tier in paths], [[0.05, 10, 100], [5, 10, 100]])
        self.assertEqual(paths[0][1]["capacity_bytes"], 80 * 16 * 2**30)
        self.assertEqual(paths[0][2]["capacity_bytes"], 2400 * 16 * 2**30)

    def test_weighted_latency_and_serial_path(self):
        local = wsc.hierarchy_path(0.1e-6, 20e9, 1, 1)
        rack = wsc.hierarchy_path(0.1e-6, 20e9, 1, 80, [(99.9e-6, 100e6)])
        array = wsc.hierarchy_path(0.1e-6, 20e9, 1, 2400,
                                   [(99.9e-6, 100e6), (400e-6, 10e6)])
        self.assertAlmostEqual(wsc.hierarchy_access_time([local, rack, array],
                                                        [0.9, 0.09, 0.01]), 14.09e-6)
        self.assertAlmostEqual(wsc.hierarchy_access_time([local, rack, array],
                                                        [0.9, 0.09, 0.01], 1000),
                               14.09e-6 + 0.9 * 1000 / 20e9
                               + 0.09 * 1000 / 100e6 + 0.01 * 1000 / 10e6)

    def test_invalid_hierarchy_parameters(self):
        path = wsc.hierarchy_path(0, 1, 1, 1)
        calls = (lambda: wsc.hierarchy_path(0, 1, 1, 0),
                 lambda: wsc.hierarchy_path(0, 1, 1, 1, [(0, 0)]),
                 lambda: wsc.hierarchy_access_time([path], [0.9]),
                 lambda: wsc.hierarchy_access_time([path], [-1]),
                 lambda: wsc.hierarchy_access_time([], []))
        for call in calls:
            with self.assertRaises(ValueError):
                call()


class PublishedCaseStudyTests(unittest.TestCase):
    def test_sixth_and_seventh_edition_financed_cost(self):
        # 6th ed. 2017, section 6.4, Figures 6.13 and 6.14; the 7th ed.
        # repeats the Hamilton 8 MW scenario in its section 6.4, Figure 6.32.
        # Values below use the displayed rounded CAPEX, not hidden spreadsheet inputs.
        assets = {"servers": (66_700_000, 36), "network": (12_810_000, 48),
                  "power_cooling": (88_000_000 * .82, 120),
                  "other_facility": (88_000_000 * .18, 120)}
        result = wsc.monthly_wsc_cost(8000, .8, 1.45, .07, assets, .05, 85000,
                                      server_count=45978)
        self.assertEqual(result["capital_total"], 167_510_000)
        self.assertEqual(result["average_it_kw"], 6400)
        self.assertAlmostEqual(result["facility_kw"], 9280)
        self.assertAlmostEqual(result["facility_kwh"], 6_774_400)
        self.assertAlmostEqual(result["electricity"], 474_208)
        # Independently calculated monthly annuity factors, with the displayed
        # textbook figure rounded to the nearest $5,000.
        expected = {"servers": 1_999_058.8368811936, "network": 295_005.25063998275,
                    "power_cooling": 765_368.7579651691, "other_facility": 168_007.77613869566}
        for name, value in expected.items():
            self.assertAlmostEqual(result["capital_payments"][name], value, places=5)
        self.assertAlmostEqual(result["monthly_total"], 3_786_648.621625031, places=4)
        self.assertAlmostEqual(result["cost_per_server_hour"], .11281895455733239, places=12)
        # Figure's networking row is $290k; rounded displayed inputs yield $295k.
        self.assertLess(abs(result["capital_payments"]["network"] - 290_000), 5100)
        self.assertLess(abs(result["monthly_total"] - 3_800_000), 15000)

    def test_power_price_extremes_and_zero_interest(self):
        assets = {"facility": (1200, 12)}
        low = wsc.monthly_wsc_cost(8000, .8, 1.45, .03, assets, 0, 0)
        high = wsc.monthly_wsc_cost(8000, .8, 1.45, .15, assets, 0, 0)
        self.assertEqual(low["capital_payments"]["facility"], 100)
        self.assertAlmostEqual(low["electricity"], 203_232)
        self.assertAlmostEqual(high["electricity"], 1_016_160)
        self.assertAlmostEqual(wsc.monthly_capital_payment(1200, 0, 12), 100)
        self.assertAlmostEqual(wsc.monthly_capital_payment(1200, 1e-16, 12), 100, places=10)
        self.assertIsNone(low["cost_per_server_hour"])
        for call in (lambda: wsc.monthly_capital_payment(1, -.1, 12),
                     lambda: wsc.monthly_capital_payment(1, 0, True),
                     lambda: wsc.monthly_wsc_cost(1, 1.1, 1, 1, assets, 0, 0),
                     lambda: wsc.monthly_wsc_cost(1, .5, .9, 1, assets, 0, 0),
                     lambda: wsc.monthly_wsc_cost(1, .5, 1, 1, {}, 0, 0)):
            with self.assertRaises(ValueError): call()

    def test_four_m_operational_and_embodied(self):
        # 7th ed. 2025, Ch. 7, 4M discussion: rounded 7.4x and 57x for
        # Model+Machine, 1.6/1.1 PUE, 6x and 9x grid differences.
        for combined, machine, grid_gain, expected in ((7.4, 5.7, 6, 65),
                                                        (57, 14, 9, 747)):
            result = wsc.four_m_carbon(1000, combined/machine, machine,
                                       1.6, 1.1, .6, .6/grid_gain,
                                       baseline_embodied_kg=40, target_embodied_kg=100)
            self.assertAlmostEqual(result["baseline_operational_kg"], 960)
            self.assertAlmostEqual(result["after_machine_kg"], 960/combined)
            self.assertAlmostEqual(result["operational_reduction"], expected, delta=1)
            self.assertAlmostEqual(result["target_total_kg"], result["target_operational_kg"]+100)
            self.assertLess(result["total_reduction"], result["operational_reduction"])
        zero = wsc.four_m_carbon(100, 1, 1, 1, 1, .5, 0)
        self.assertIsNone(zero["operational_reduction"])
        for call in (lambda: wsc.four_m_carbon(1, 0, 1, 1, 1, 1, 1),
                     lambda: wsc.four_m_carbon(1, 1, 1, 1, .5, 1, 1),
                     lambda: wsc.four_m_carbon(1, 1, 1, 1, 1, -1, 1)):
            with self.assertRaises(ValueError): call()


if __name__ == "__main__":
    unittest.main()
