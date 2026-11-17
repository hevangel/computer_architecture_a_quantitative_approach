import itertools
import unittest

import rv32im_traffic as rv


class RiscVTrafficTests(unittest.TestCase):
    def test_instruction_encodings(self):
        # Literal instruction words checked independently against the R/I/S/B layouts.
        self.assertEqual(rv.lw(1, 0, 0), 0x00002083)
        self.assertEqual(rv.sw(3, 0, 16), 0x00302823)
        self.assertEqual(rv.alu("add", 3, 1, 2), 0x002081b3)
        self.assertEqual(rv.alu("sub", 3, 1, 2), 0x402081b3)
        self.assertEqual(rv.alu("mul", 3, 1, 2), 0x022081b3)
        self.assertEqual(rv.bge(2, 1, 12), 0x00115663)

    def test_expression_and_wraparound(self):
        program = rv.expression_program()
        result = rv.execute(program, {0: 2, 4: 3, 8: 11, 12: 7})
        self.assertEqual(result["memory"][16], 20)
        self.assertEqual((result["instructions"], result["static_code_bytes"],
                          result["dynamic_code_bytes"], result["data_read_bytes"],
                          result["data_write_bytes"]), (9, 36, 36, 16, 4))
        overflow = rv.execute(program, {0: 0xffffffff, 4: 2, 8: -2, 12: 1})
        self.assertEqual(overflow["memory"][16], 0xfffffffd)

    def test_sort_signed_permutations(self):
        program = rv.sort_program(4)
        for values in itertools.permutations([-2, -1, 1, 2]):
            result = rv.execute(program, {4 * i: value for i, value in enumerate(values)})
            got = [rv._signed(result["memory"][4 * i], 32) for i in range(4)]
            self.assertEqual(got, sorted(values))
        result = rv.execute(program, {0: 4, 4: 1, 8: 3, 12: 2})
        self.assertEqual((result["instructions"], result["static_code_bytes"],
                          result["dynamic_code_bytes"], result["data_read_bytes"],
                          result["data_write_bytes"]), (27, 124, 108, 48, 32))

    def test_zero_register_and_signed_offsets(self):
        # x0 ignores writes; negative load/store offsets and a backward BGE are decoded.
        code = [rv.lw(1, 0, 4), rv.lw(0, 0, 0), rv.sw(0, 1, -4), rv.EBREAK]
        result = rv.execute(code, {0: 99, 4: 8})
        self.assertEqual(result["memory"][4], 0)
        self.assertEqual(result["registers"][0], 0)
        with self.assertRaisesRegex(ValueError, "instruction limit"):
            rv.execute([rv.lw(1, 0, 0), rv.bge(0, 0, -4), rv.EBREAK], {}, max_instructions=3)

    def test_reject_invalid(self):
        for call in (lambda: rv.bge(0, 0, 3), lambda: rv.lw(32, 0, 0),
                     lambda: rv.sw(0, 0, 2048), lambda: rv.execute([0], {}),
                     lambda: rv.execute([rv.lw(1, 0, 1), rv.EBREAK], {})):
            with self.assertRaises(ValueError):
                call()


if __name__ == "__main__":
    unittest.main()
