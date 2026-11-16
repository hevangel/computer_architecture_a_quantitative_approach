import itertools
import unittest

import mips64_traffic as mips


class MipsTrafficTests(unittest.TestCase):
    def test_binary_encodings(self):
        self.assertEqual(mips.ld(1, 0, 0), 0xdc010000)
        self.assertEqual(mips.sd(3, 0, 32), 0xfc030020)
        self.assertEqual(mips.r_type("daddu", 3, 1, 2), 0x0022182d)
        self.assertEqual(mips.r_type("dsubu", 3, 1, 2), 0x0022182f)
        self.assertEqual(mips.r_type("slt", 3, 1, 2), 0x0022182a)
        self.assertEqual(mips.dmult(1, 2), 0x0022001c)
        self.assertEqual(mips.mflo(3), 0x00001812)
        self.assertEqual(mips.beq(3, 0, 3), 0x10600003)

    def test_expression_and_signed_multiply(self):
        code = mips.expression_program()
        result = mips.execute(code, {0: 2, 8: 3, 16: 11, 24: 7})
        self.assertEqual(result["memory"][32], 20)
        self.assertEqual((result["instructions"], result["static_code_bytes"],
                          result["dynamic_code_bytes"], result["data_read_bytes"],
                          result["data_write_bytes"]), (10, 40, 40, 32, 8))
        negative = mips.execute(code, {0: -1, 8: 2, 16: -2, 24: 1})
        self.assertEqual(negative["memory"][32], (1 << 64) - 3)
        self.assertEqual(negative["hi"], (1 << 64) - 1)

    def test_sort_permutations_and_counts(self):
        code = mips.sort_program(4)
        for values in itertools.permutations([-2, -1, 1, 2]):
            result = mips.execute(code, {8 * i: v for i, v in enumerate(values)})
            got = [mips._signed(result["memory"][8 * i], 64) for i in range(4)]
            self.assertEqual(got, sorted(values))
        result = mips.execute(code, {0: 4, 8: 1, 16: 3, 24: 2})
        self.assertEqual((result["instructions"], result["static_code_bytes"],
                          result["dynamic_code_bytes"], result["data_read_bytes"],
                          result["data_write_bytes"]), (39, 172, 156, 96, 64))

    def test_delay_slots_and_zero_register(self):
        # Taken branch still executes the store in its delay slot; the second
        # store is skipped. A load into r0 must not change the zero register.
        code = [mips.ld(1, 0, 0), mips.ld(0, 0, 8), mips.beq(0, 0, 2),
                mips.sd(1, 0, 16), mips.sd(1, 0, 24), mips.BREAK]
        result = mips.execute(code, {0: 17, 8: 99})
        self.assertEqual(result["memory"][16], 17)
        self.assertNotIn(24, result["memory"])
        self.assertEqual(result["registers"][0], 0)
        with self.assertRaisesRegex(ValueError, "branch in branch delay slot"):
            mips.execute([mips.beq(0, 0, 1), mips.beq(0, 0, 0), mips.BREAK], {})
        # The negative offset points back to the load, not to the branch.
        with self.assertRaisesRegex(ValueError, "instruction limit"):
            mips.execute([mips.ld(1, 0, 0), mips.beq(0, 0, -2), mips.NOP, mips.BREAK], {}, 5)

    def test_invalid_instructions_and_addresses(self):
        for call in (lambda: mips.ld(32, 0, 0), lambda: mips.sd(0, 0, 32768),
                     lambda: mips.execute([0xffffffff], {}),
                     lambda: mips.execute([mips.ld(1, 0, 4), mips.BREAK], {})):
            with self.assertRaises(ValueError):
                call()


if __name__ == "__main__":
    unittest.main()
