import itertools
import unittest

import isa_class_traffic as isa
import rv32im_traffic as rv
import mips64_traffic as mips


class ISATrafficTests(unittest.TestCase):
    def test_textbook_four_class_addition(self):
        # 5th ed. Fig. A.2 (PDF p. 527), 1st ed. Fig. 3.3 (PDF p. 122).
        # Fig. A.2 contains four, three, three and four body instructions.
        # Interpreter halt and toy encoding lengths are separate assumptions.
        body_counts = {"stack": 4, "accumulator": 3, "register_memory": 3, "load_store": 4}
        body_bytes = {"stack": 10, "accumulator": 9, "register_memory": 12, "load_store": 16}
        for values in ((2, 3), (-5, 8), (0, 0), (100, -100)):
            for style in isa.STYLES:
                options = {"stack_storage": "internal"} if style == "stack" else {}
                memory = {0: values[0], 1: values[1], 2: 999}
                result = isa.execute(style, isa.addition_program(style), memory, **options)
                self.assertEqual(result["memory"][2], sum(values))
                self.assertEqual((result["memory"][0], result["memory"][1]), values)
                self.assertEqual(result["instructions"]-1, body_counts[style])
                self.assertEqual(result["static_code_bytes"]-isa.SIZES[style]["halt"], body_bytes[style])
                self.assertEqual((result["data_read_bytes"], result["data_write_bytes"]), (8, 4))
        resident = isa.execute("stack", isa.addition_program("stack"), {0: 2, 1: 3}, stack_storage="internal")
        backed = isa.execute("stack", isa.addition_program("stack"), {0: 2, 1: 3})
        self.assertEqual((resident["data_read_bytes"], resident["data_write_bytes"]), (8, 4))
        self.assertEqual((backed["data_read_bytes"], backed["data_write_bytes"]), (20, 16))
        self.assertEqual(backed["memory"][2], resident["memory"][2])
        with self.assertRaises(ValueError):
            isa.execute("stack", isa.addition_program("stack"), {}, stack_storage="unknown")
        with self.assertRaises(ValueError):
            isa.execute("load_store", isa.addition_program("load_store"), {}, stack_storage="internal")

    def test_encoded_load_store_addition(self):
        # Same four-operation load/store body, encoded in two real ISAs.
        self.assertEqual(rv.addition_program(),
                         [0x00002083, 0x00402103, 0x002081b3, 0x00302423, rv.EBREAK])
        self.assertEqual(mips.addition_program(),
                         [0xdc010000, 0xdc020008, 0x0022182d, 0xfc030010, mips.BREAK])
        for implementation, word_bytes, mask in ((rv, 4, 0xffffffff), (mips, 8, (1 << 64)-1)):
            for a, b in ((2, 3), (-5, 8), (mask, 2)):
                result = implementation.execute(implementation.addition_program(),
                                                {0: a, word_bytes: b, 2*word_bytes: 999})
                self.assertEqual(result["memory"][2*word_bytes], (a+b)&mask)
                self.assertEqual(result["instructions"], 5)
                self.assertEqual(result["static_code_bytes"], 20)
                self.assertEqual(result["dynamic_code_bytes"], 20)
                self.assertEqual((result["data_read_bytes"], result["data_write_bytes"]),
                                 (2*word_bytes, word_bytes))

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
