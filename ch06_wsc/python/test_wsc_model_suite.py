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


if __name__ == "__main__":
    unittest.main()
