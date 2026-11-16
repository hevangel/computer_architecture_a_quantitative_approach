"""Independent reference for the two predictor traces used by the HDL tests."""
import unittest


class Predictor:
    def __init__(self):
        self.local_history = [0] * 4
        self.global_history = 0
        self.local = [1] * 16
        self.global_ = [1] * 4
        self.choice = [1] * 4

    @staticmethod
    def saturate(counter, taken):
        return min(3, counter + 1) if taken else max(0, counter - 1)

    def step(self, pc_index, taken):
        local_index = pc_index * 4 + self.local_history[pc_index]
        global_index = self.global_history
        local = self.local[local_index] >= 2
        global_ = self.global_[global_index] >= 2
        tournament = global_ if self.choice[pc_index] >= 2 else local
        if local != global_:
            self.choice[pc_index] = self.saturate(self.choice[pc_index], global_ == taken)
        self.local[local_index] = self.saturate(self.local[local_index], taken)
        self.global_[global_index] = self.saturate(self.global_[global_index], taken)
        self.local_history[pc_index] = (self.local_history[pc_index] * 2 + taken) & 3
        self.global_history = (self.global_history * 2 + taken) & 3
        return local, global_, tournament


class PredictorReferenceTest(unittest.TestCase):
    def test_periodic_and_correlated_counts(self):
        predictor, counts = Predictor(), [0, 0, 0]
        for k in range(2048):
            index, phase = k % 4, (k // 4) % 4
            actual = int(phase in ((0, 1) if index % 2 == 0 else (0, 3)))
            predictions = predictor.step(index, actual)
            if k >= 128:
                counts = [total + (prediction == actual) for total, prediction in zip(counts, predictions)]
        self.assertEqual(counts, [1920, 1440, 1920])
        predictor, counts, state, actual = Predictor(), [0, 0, 0], 0x12345678, 0
        for k in range(4096):
            if k % 2 == 0:
                state = (state * 1664525 + 1013904223) & 0xffffffff
                actual = state >> 31
            predictions = predictor.step(k % 2, actual)
            if k >= 256:
                counts = [total + (prediction == actual) for total, prediction in zip(counts, predictions)]
        self.assertEqual(counts, [1994, 2724, 2736])


if __name__ == "__main__":
    unittest.main()
