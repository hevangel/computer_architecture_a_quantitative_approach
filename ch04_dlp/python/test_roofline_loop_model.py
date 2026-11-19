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


class NestAndTextbookTests(unittest.TestCase):
    def test_sixth_edition_vector_and_cpu_rooflines(self):
        # 6th ed., sec. 4.3, Fig. 4.11: GFLOP/s and GB/s.
        for intensity, sx_expected, core_expected in ((0.25, 40.5, 4.1),
                                                       (4, 102.4, 42.66)):
            sx = model.roofline(102.4, 162, intensity)
            core = model.roofline(42.66, 16.4, intensity)
            self.assertAlmostEqual(sx[1], sx_expected)
            self.assertAlmostEqual(core[1], core_expected)
        self.assertAlmostEqual(model.roofline(102.4, 162, 1)[0], 102.4 / 162)
        self.assertAlmostEqual(model.roofline(42.66, 16.4, 1)[0], 42.66 / 16.4)

    def test_sixth_edition_cpu_gpu_and_saxpy(self):
        # 6th ed. Fig. 4.28, p. 381: bandwidth measured at processor.
        targets = {"i7_dp": (42.66, 16.4), "gtx_dp": (78, 127),
                   "i7_sp": (85.33, 16.4), "gtx_sp": (624, 127)}
        low = model.compare_rooflines(targets, 1, 2)
        self.assertAlmostEqual(low["i7_dp"][1], 8.2)
        self.assertAlmostEqual(low["gtx_dp"][1], 63.5)
        high = model.compare_rooflines(targets, 4, 1)
        self.assertAlmostEqual(high["i7_dp"][1], 42.66)
        self.assertAlmostEqual(high["gtx_dp"][1], 78)
        self.assertAlmostEqual(high["i7_sp"][1], 65.6)
        self.assertAlmostEqual(high["gtx_sp"][1], 508)
        # One SAXPY update, 2 FLOPs and 12 bytes for two reads and one write.
        saxpy = model.compare_rooflines(targets, 2, 12)
        self.assertAlmostEqual(saxpy["i7_sp"][1], 16.4 / 6)
        self.assertAlmostEqual(saxpy["gtx_sp"][1], 127 / 6)
        self.assertEqual(saxpy["gtx_sp"][2], "memory")
        self.assertAlmostEqual(saxpy["gtx_sp"][1] / saxpy["i7_sp"][1], 127 / 16.4)
        with self.assertRaises(ValueError):
            model.kernel_intensity(1, 0)

    def test_affine_nested_witness_and_filter(self):
        # row-major A[4*i+j] followed by A[4*i+j-1].
        ranges = (range(3), range(4))
        self.assertEqual(model.affine_nest_witness((4, 1), 0, (4, 1), -1, ranges),
                         ((0, 0), (0, 1)))
        self.assertFalse(model.affine_nest_may_alias((4, 2), 0, (4, 2), 1))
        self.assertIsNone(model.affine_nest_witness((4, 2), 0, (4, 2), 1, ranges))
        self.assertTrue(model.affine_nest_may_alias((4, 1), 0, (4, 1), -100))
        self.assertIsNone(model.affine_nest_witness((4, 1), 0, (4, 1), -100, ranges))
        self.assertEqual(model.affine_nest_witness((4, 1), 0, (4, 1), 1,
                                                   (range(2, -1, -1), range(3, -1, -1))),
                         ((2, 3), (2, 2)))
        with self.assertRaises(ValueError):
            model.affine_nest_witness((1,), 0, (1,), 0, (range(2), range(2)))

    def test_nest_matches_brute_force(self):
        from itertools import product
        ranges = (range(2), range(3))
        iterations = list(product(*ranges))
        for a in product(range(-1, 2), repeat=2):
            for c in product(range(-1, 2), repeat=2):
                for offset in range(-2, 3):
                    expected = next(((x, y) for ix, y in enumerate(iterations)
                                     for x in iterations[:ix]
                                     if sum(k*v for k, v in zip(a, x)) ==
                                        sum(k*v for k, v in zip(c, y)) + offset), None)
                    witness = model.affine_nest_witness(a, 0, c, offset, ranges)
                    self.assertEqual(witness, expected)


class DependenceClassificationTests(unittest.TestCase):
    def test_loop_carried_flow_and_separate_arrays(self):
        A = model.AffineAccess
        result = model.classify_affine_dependences([
            A("read_prev", "A", "read", (1,), -1),
            A("write", "A", "write", (1,)),
            A("other", "B", "read", (1,))], (range(4),))
        self.assertEqual(len(result), 1)
        dep = result[0]
        self.assertEqual((dep.source, dep.target, dep.kind), ("write", "read_prev", "flow"))
        self.assertEqual((dep.source_iteration, dep.target_iteration, dep.distance, dep.direction),
                         ((0,), (1,), (1,), ("+",)))
        self.assertTrue(dep.carried)

    def test_same_iteration_order_and_descending_direction(self):
        A = model.AffineAccess
        result = model.classify_affine_dependences([
            A("load", "A", "read", (0,)), A("store", "A", "write", (0,))],
            (range(2, -1, -1),))
        facts = {(d.source, d.target, d.kind, d.direction, d.carried) for d in result}
        self.assertIn(("load", "store", "anti", ("=",), False), facts)
        self.assertIn(("store", "load", "flow", ("-",), True), facts)
        self.assertIn(("load", "store", "anti", ("-",), True), facts)
        self.assertIn(("store", "store", "output", ("-",), True), facts)
        self.assertNotIn(("load", "load", "flow", ("-",), True), facts)

    def test_nest_mixed_direction(self):
        A = model.AffineAccess
        result = model.classify_affine_dependences([
            A("write", "A", "write", (2, 1)),
            A("read", "A", "read", (2, 1))], (range(2), range(3)))
        self.assertTrue(any(d.kind == "flow" and d.source_iteration == (0, 2) and
                            d.target_iteration == (1, 0) and d.direction == ("+", "-")
                            for d in result))
        self.assertTrue(any(not d.carried and d.kind == "flow" for d in result))

    def test_against_exhaustive_event_pairs(self):
        from itertools import product
        A = model.AffineAccess
        bounds = (range(2), range(2, -1, -1))
        for a, b in product(range(-1, 2), repeat=2):
            accesses = (A("r", "A", "read", (a, 1)),
                        A("w", "A", "write", (b, -1)),
                        A("x", "B", "write", (1, 0)))
            events = [(it, op) for it in product(*bounds) for op in accesses]
            expected = set()
            for j, (later, dst) in enumerate(events):
                dst_address = dst.offset + sum(c*v for c, v in zip(dst.coefficients, later))
                for earlier, src in events[:j]:
                    src_address = src.offset + sum(c*v for c, v in zip(src.coefficients, earlier))
                    if src.array != dst.array or src_address != dst_address or src.mode == dst.mode == "read":
                        continue
                    kind = ("flow" if (src.mode, dst.mode) == ("write", "read") else
                            "anti" if (src.mode, dst.mode) == ("read", "write") else "output")
                    delta = tuple(y-x for x, y in zip(earlier, later))
                    direction = tuple("+" if x > 0 else "-" if x < 0 else "=" for x in delta)
                    expected.add((src.name, dst.name, kind, direction, any(delta)))
            witnesses = model.classify_affine_dependences(accesses, bounds)
            actual = {(d.source, d.target, d.kind, d.direction, d.carried) for d in witnesses}
            self.assertEqual(actual, expected)
            by_name = {access.name: access for access in accesses}
            positions = {iteration: i for i, iteration in enumerate(product(*bounds))}
            for witness in witnesses:
                src, dst = by_name[witness.source], by_name[witness.target]
                self.assertEqual(src.array, dst.array)
                self.assertEqual(src.offset + sum(c*v for c, v in zip(src.coefficients, witness.source_iteration)),
                                 dst.offset + sum(c*v for c, v in zip(dst.coefficients, witness.target_iteration)))
                self.assertLessEqual(positions[witness.source_iteration], positions[witness.target_iteration])
                if not witness.carried:
                    self.assertLess(accesses.index(src), accesses.index(dst))

    def test_invalid_inputs_and_empty_iteration_space(self):
        A = model.AffineAccess
        self.assertEqual(model.classify_affine_dependences([A("r", "A", "read", (1,))], (range(0),)), ())
        for accesses, bounds in (([], (range(2),)),
                                 ([A("r", "A", "read", (1,))], ()),
                                 ([A("r", "A", "read", (True,))], (range(2),)),
                                 ([A("r", "A", "other", (1,))], (range(2),)),
                                 ([A("r", "A", "read", (1,)), A("r", "B", "write", (1,))], (range(2),))):
            with self.subTest(accesses=accesses, bounds=bounds), self.assertRaises(ValueError):
                model.classify_affine_dependences(accesses, bounds)

    def test_roofline_cross_edition_examples(self):
        # 5th ed. Fig. 4.28 p. 355; 6th ed. Fig. 4.28 p. 381;
        # 7th ed. Fig. 4.31: the same published Core i7 920 / GTX 280 parameters.
        for edition in (5, 6, 7):
            with self.subTest(edition=edition):
                targets = {"i7": (42.66, 16.4), "gtx": (78, 127)}
                self.assertAlmostEqual(model.compare_rooflines(targets, 1, 2)["i7"][1], 8.2)
                self.assertAlmostEqual(model.compare_rooflines(targets, 4, 1)["gtx"][1], 78)


if __name__ == "__main__":
    unittest.main()
