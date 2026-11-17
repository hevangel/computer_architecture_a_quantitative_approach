import math
import unittest

import io_queueing_unit as q


class QueueingTests(unittest.TestCase):
    def test_mm1_and_little(self):
        rho, wait, response = q.mm1(8, 10)
        self.assertAlmostEqual(rho, 0.8)
        self.assertAlmostEqual(wait, 0.4)
        self.assertAlmostEqual(response, 0.5)
        self.assertAlmostEqual(q.littles_law(8, response), 4)
        self.assertGreater(q.mm1(9, 10)[2], response)

    def test_mg1_deterministic_and_mm1_equivalence(self):
        self.assertAlmostEqual(q.mg1(8, 0.1, 0.01)[1], 0.2)
        for left, right in zip(q.mg1(8, 0.1, 0.02), q.mm1(8, 10)):
            self.assertAlmostEqual(left, right)

    def test_mmm_closed_form_and_single_server(self):
        rho, probability, wait, response = q.mmm(2, 2, 2)
        self.assertAlmostEqual(rho, 0.5)
        self.assertAlmostEqual(probability, 1 / 3)
        self.assertAlmostEqual(wait, 1 / 6)
        self.assertAlmostEqual(response, 2 / 3)
        single = q.mmm(8, 10, 1)
        for left, right in zip((single[0], single[2], single[3]), q.mm1(8, 10)):
            self.assertAlmostEqual(left, right)
        self.assertEqual(q.mmm(0, 1, 1000), (0, 0, 0, 1))

    def test_disk_and_raid(self):
        self.assertAlmostEqual(q.disk_service_time(4, 1, 2, 8, 100, 100), 10)
        afr, years = 0.1, 0.25
        p = 1 - (1 - afr) ** years
        self.assertAlmostEqual(q.rebuild_loss_probability(4, 1, afr, years), 1 - (1 - p) ** 3)
        self.assertAlmostEqual(q.rebuild_loss_probability(4, 2, afr, years), 3 * p * p * (1 - p) + p ** 3)
        tiny = q.rebuild_loss_probability(3, 2, 1e-8, 1e-3)
        expected = math.expm1(math.log1p(-1e-8) * 1e-3) ** 2
        self.assertLess(abs(tiny / expected - 1), 1e-12)

    def test_invalid_inputs(self):
        for call in (lambda: q.mm1(10, 10), lambda: q.mmm(4, 2, 2),
                     lambda: q.mmm(1, 1, 0), lambda: q.mg1(1, 1, 0.5),
                     lambda: q.disk_service_time(-1, 0, 0, 1, 1, 1),
                     lambda: q.rebuild_loss_probability(4, 2, 1, 1)):
            with self.assertRaises(ValueError):
                call()

    def test_raid_mttdl_birth_death(self):
        rate, repair = 0.02, 0.5
        afr = -math.expm1(-rate)
        # First-step solution of three RAID-5 states: 0, 1 and absorbing 2.
        expected5 = 1 / (4 * rate) + 1 / (3 * rate) + (1 / repair) / (12 * rate ** 2)
        self.assertAlmostEqual(q.raid_mttdl(4, 1, afr, repair) / expected5, 1, places=12)
        # Independent first-step equations for a four-disk RAID-6 chain.
        t0 = q.raid_mttdl(4, 2, afr, repair)
        d0 = 1 / (4 * rate)
        d1 = (1 + d0 / repair) / (3 * rate)
        d2 = (1 + d1 / repair) / (2 * rate)
        self.assertAlmostEqual(t0 / (d0 + d1 + d2), 1, places=12)
        self.assertGreater(t0, expected5)
        self.assertGreater(q.raid_mttdl(4, 1, afr, 0.25), expected5)
        with self.assertRaises(ValueError):
            q.raid_mttdl(4, 1, 0, repair)


if __name__ == "__main__":
    unittest.main()
