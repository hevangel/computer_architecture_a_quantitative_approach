import unittest
from pathlib import Path
from tage_reference import Predictor, saturate
from generate_vectors import generate

class PredictorReferenceTests(unittest.TestCase):
    def test_saturating_counters(self):
        self.assertEqual(saturate(0, 3, False), 0)
        self.assertEqual(saturate(3, 3, True), 3)
        self.assertEqual(saturate(2, 3, True), 3)
        self.assertEqual(saturate(4, 7, False), 3)

    def test_longest_provider_and_usefulness(self):
        p = Predictor()
        p.tables[0][0] = (0, 1, 0)
        p.tables[1][0] = (0, 7, 0)
        p.tables[2][0] = (0, 0, 0)
        prediction, _, provider, alternate, _ = p.lookup(0)
        self.assertEqual((prediction, provider, alternate), (False, 2, True))
        p.update(0, False)
        self.assertEqual(p.tables[2][0], (0, 0, 1))

    def test_useful_mismatching_tags_are_not_replaced(self):
        p = Predictor()
        for bank in p.tables:
            bank[0] = (1, 3, 2)  # Valid but wrong tag, with useful state.
        self.assertEqual(p.lookup(0)[2], -1)
        p.update(0, True)
        self.assertEqual([bank[0] for bank in p.tables], [(1, 3, 1)] * 3)

    def test_generated_vectors_are_reproducible(self):
        golden = Path(__file__).resolve().parent.parent / "golden.txt"
        self.assertEqual(golden.read_text(encoding="ascii"), generate())

if __name__ == "__main__":
    unittest.main()
