import unittest
import re
from pathlib import Path
from cache_reference import Cache, traces

class CacheReferenceTests(unittest.TestCase):
    def test_associativity_and_classification(self):
        direct, associative = Cache(4, 1, "LRU"), Cache(1, 4, "LRU")
        for address in traces()[0]:
            direct.access(address); associative.access(address)
        self.assertEqual(direct.counts, [4, 0, 252])
        self.assertEqual(associative.counts, [4, 0, 0])

    def test_fifo_does_not_reorder_hits(self):
        lru, fifo = Cache(1, 4, "LRU"), Cache(1, 4, "FIFO")
        for address in [0, 1, 2, 3, 0, 4]:
            lru.access(address); fifo.access(address)
        self.assertFalse(lru.access(1))
        self.assertTrue(fifo.access(1))

    def test_capacity_and_policy(self):
        caches = [Cache(1, 4, p) for p in ("LRU", "FIFO", "RANDOM", "PLRU")]
        for address in traces()[1]:
            for cache in caches: cache.access(address)
        self.assertEqual([c.counts for c in caches], [[5, 251, 0], [5, 251, 0], [5, 110, 0], [5, 250, 0]])

    def test_hdl_golden_vectors_match_reference(self):
        base = Path(__file__).resolve().parent.parent
        sv = (base / "sv/tb_cache_3c_policies.sv").read_text()
        vhdl = (base / "vhdl/tb_cache_3c_policies.vhd").read_text()
        sv_vectors = {(int(t), int(d)): int(bits, 16) for t, d, bits in
                      re.findall(r"expected_kind\[(\d+)\]\[(\d+)\]=512'h([0-9a-f]{128})", sv)}
        vhdl_vectors = [int(bits, 16) for bits in re.findall(r'x"([0-9a-f]{128})"', vhdl)]
        configs = [(4, 1, "LRU"), (2, 2, "LRU"), (1, 3, "LRU"), (1, 4, "LRU"),
                   (1, 4, "FIFO"), (1, 4, "RANDOM"), (1, 4, "PLRU"),
                   (1, 3, "PLRU"), (1, 3, "RANDOM"), (2, 2, "PLRU"), (4, 1, "PLRU")]
        self.assertEqual(len(sv_vectors), 33)
        self.assertEqual(len(vhdl_vectors), 33)
        for t, trace in enumerate(traces()):
            for d, config in enumerate(configs):
                model, packed = Cache(*config), 0
                for i, address in enumerate(trace):
                    previous = model.counts.copy()
                    hit = model.access(address)
                    kind = 0 if hit else 1 + next(j for j in range(3) if model.counts[j] != previous[j])
                    packed |= kind << (2 * i)
                self.assertEqual(sv_vectors[t, d], packed)
                self.assertEqual(vhdl_vectors[t * len(configs) + d], packed)

    def test_invalid_inputs(self):
        with self.assertRaises(ValueError): Cache(1, 5, "LRU")
        with self.assertRaises(ValueError): Cache(1, 4, "bad")
        with self.assertRaises(ValueError): Cache(1, 4, "LRU").access(256)

if __name__ == "__main__": unittest.main()
