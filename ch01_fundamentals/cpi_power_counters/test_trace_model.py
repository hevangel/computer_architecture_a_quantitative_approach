"""Independent arithmetic for the stimulus in both HDL testbenches.

This validates the expected trace values, not the RTL; run an HDL simulator to
verify the designs themselves.
"""
import unittest


def trace_model(retire_count, gated):
    retired_classes = [0] * 4
    stall_classes = [0] * 4
    last = transitions = 0
    last_dynamic = 0
    for cycle in range(10):
        if cycle < retire_count:
            retired_classes[cycle % 4] += 1
        else:
            stall_classes[cycle % 4] += 1
        value = 0xffffffff if cycle % 2 == 0 else 0
        active = not gated or cycle % 4 < 2
        count = (value ^ last).bit_count() if active else 0
        if active:
            last = value
        transitions += count
        last_dynamic = count * 65536
    return {"cycles": 10, "retired": retire_count, "stalls": 10-retire_count,
            "cpi_q16": (10 << 16) // retire_count, "retired_classes": retired_classes,
            "stall_classes": stall_classes, "toggles": transitions,
            "dynamic_q16": transitions * 65536, "static_q16": 10 * 16384,
            "last_power_q16": last_dynamic + 16384}


class TraceModelTests(unittest.TestCase):
    def test_testbench_constants(self):
        base = trace_model(6, False)
        improved = trace_model(8, True)
        self.assertEqual(base, {"cycles": 10, "retired": 6, "stalls": 4, "cpi_q16": 109226,
                                "retired_classes": [2, 2, 1, 1], "stall_classes": [1, 1, 1, 1],
                                "toggles": 320, "dynamic_q16": 20971520, "static_q16": 163840,
                                "last_power_q16": 2113536})
        self.assertEqual(improved, {"cycles": 10, "retired": 8, "stalls": 2, "cpi_q16": 81920,
                                    "retired_classes": [2, 2, 2, 2], "stall_classes": [1, 1, 0, 0],
                                    "toggles": 192, "dynamic_q16": 12582912, "static_q16": 163840,
                                    "last_power_q16": 2113536})
        self.assertLessEqual(improved["dynamic_q16"] * 10, base["dynamic_q16"] * 7)


if __name__ == "__main__":
    unittest.main()
