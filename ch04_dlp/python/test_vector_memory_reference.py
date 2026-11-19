import unittest
import vector_memory_reference as ref


class VectorMemoryTests(unittest.TestCase):
    def test_stride_conflicts_and_strip_mining(self):
        memory = list(range(1024))
        unit = ref.vector_memory(memory, range(45))
        self.assertEqual(unit['strip_lengths'], [16, 16, 13])
        self.assertEqual(unit['loads'], list(range(45)))
        self.assertEqual((unit['service_cycles'], unit['ideal_cycles'], unit['bank_stall_cycles']), (6, 6, 0))
        stride = ref.vector_memory(memory, [8 * i for i in range(16)])
        self.assertEqual((stride['service_cycles'], stride['ideal_cycles'], stride['bank_stall_cycles']), (16, 2, 14))
        self.assertEqual(stride['service_cycles'] / ref.vector_memory(memory, range(16))['service_cycles'], 8)

    def test_sparse_gather_scatter_and_duplicate_order(self):
        original = list(range(64))
        addresses = [31, 4, 9, 31, 0, 60, 18, 2, 31]
        values = [91, 92, 93, 94, 95, 96, 97, 98, 99]
        result = ref.vector_memory(original, addresses, stores=values, mvl=4)
        expected = original.copy()
        for addr, value in zip(addresses, values): expected[addr] = value
        self.assertEqual(result['memory'], expected)
        self.assertEqual(original, list(range(64)))
        gathered = ref.vector_memory(result['memory'], addresses, mvl=4)
        self.assertEqual(gathered['loads'], [expected[a] for a in addresses])
        self.assertEqual(result['memory'][31], 99)

    def test_trace_and_startup_metrics(self):
        result = ref.vector_memory(list(range(32)), [0, 8, 1, 9], mvl=16, startup_cycles=3)
        self.assertEqual(result['trace'], [(0, 2), (1, 3)])
        self.assertEqual(result['elapsed_cycles'], 5)
        self.assertEqual(ref.asymptotic_metrics(8, 3, 2, 4), {'r_infinity': 2, 'n_half': 6})
        self.assertEqual(ref.vector_memory([], [])['strip_lengths'], [])

    def test_invalid_input(self):
        for call in (lambda: ref.strip_lengths(-1, 16), lambda: ref.strip_lengths(1, 0),
                     lambda: ref.vector_memory([1], [1]), lambda: ref.vector_memory([1], [0], stores=[]),
                     lambda: ref.vector_memory([1], [0], banks=0),
                     lambda: ref.asymptotic_metrics(8, 1, 1, 9)):
            with self.assertRaises(ValueError): call()


if __name__ == '__main__':
    unittest.main()
