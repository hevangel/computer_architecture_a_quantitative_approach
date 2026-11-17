import itertools
import unittest

import isa_class_traffic as isa


class ISATrafficTests(unittest.TestCase):
    def test_expression_results_and_hand_counted_traffic(self):
        # Counts follow directly from the listed instruction streams. For stack,
        # each push writes a word and each pop reads a word in addition to loads.
        expected = {
            "stack": (9, 19, 44, 32),
            "accumulator": (8, 22, 20, 8),
            "register_memory": (8, 29, 20, 8),
            "load_store": (9, 36, 16, 4),
        }
        for style in isa.STYLES:
            with self.subTest(style=style):
                result = isa.execute(style, isa.expression_program(style), {0: 2, 1: 3, 2: 11, 3: 7})
                self.assertEqual(result["memory"][4], 20)
                self.assertEqual((result["instructions"], result["static_code_bytes"],
                                  result["data_read_bytes"], result["data_write_bytes"]), expected[style])
                self.assertEqual(result["dynamic_code_bytes"], result["static_code_bytes"])

    def test_sort_all_permutations_and_repeated_values(self):
        for style in isa.STYLES:
            program = isa.sort_program(style, 4)
            for values in itertools.permutations(range(4)):
                result = isa.execute(style, program, dict(enumerate(values)))
                self.assertEqual([result["memory"][i] for i in range(4)], sorted(values))
            values = [2, -1, 2, -1]
            result = isa.execute(style, program, dict(enumerate(values)))
            self.assertEqual([result["memory"][i] for i in range(4)], sorted(values))

    def test_sort_counts_are_sensitive_to_swaps(self):
        # Four inversions and six comparisons: register-memory uses 3
        # instructions/comparison, 3/swap, plus halt; load-store uses 4 and 2.
        memory = dict(enumerate([4, 1, 3, 2]))
        rm = isa.execute("register_memory", isa.sort_program("register_memory", 4), memory)
        ls = isa.execute("load_store", isa.sort_program("load_store", 4), memory)
        self.assertEqual((rm["instructions"], rm["data_read_bytes"], rm["data_write_bytes"]), (31, 64, 32))
        self.assertEqual((ls["instructions"], ls["data_read_bytes"], ls["data_write_bytes"]), (33, 48, 32))
        self.assertLess(ls["dynamic_code_bytes"], ls["static_code_bytes"])

    def test_invalid_programs(self):
        with self.assertRaises(ValueError):
            isa.execute("stack", [("add",), ("halt",)], {})
        with self.assertRaises(ValueError):
            isa.execute("load_store", [("load", -1, 0), ("halt",)], {})
        with self.assertRaises(ValueError):
            isa.execute("stack", [("jle", 9)], {})
        with self.assertRaises(ValueError):
            isa.sort_program("stack", -1)


if __name__ == "__main__":
    unittest.main()
