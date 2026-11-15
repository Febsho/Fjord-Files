import argparse
import unittest

try:
    from scripts.benchmark import bounded, sample
except ModuleNotFoundError:
    from benchmark import bounded, sample


class BenchmarkTests(unittest.TestCase):
    def test_bounds(self):
        self.assertEqual(bounded("1", 5), 1)
        for value in ("0", "6", "bad"):
            with self.assertRaises((ValueError, argparse.ArgumentTypeError)):
                bounded(value, 5)

    def test_sample_calls_work_and_reports_values(self):
        calls = []
        result = sample(lambda: calls.append(1), 3)
        self.assertEqual(len(calls), 3)
        self.assertEqual(len(result["samples"]), 3)
        self.assertEqual(result["unit"], "ms")
        self.assertEqual(result["median"], sorted(result["samples"])[1])


if __name__ == "__main__":
    unittest.main()
