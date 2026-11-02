import random
import unittest
from fractions import Fraction

from exercises.conv_walkthrough import conv_trace, EXPECTED
from quant.integer_math import rne_div, multiplier_shift, requantize, aligned_add


class BasicTests(unittest.TestCase):
    def test_model_inventory(self):
        from model.resnet20_plan import build_plan
        p = build_plan()
        self.assertEqual(len(p["operations"]), 30)
        self.assertEqual(sum(o["op"] == "conv" for o in p["operations"]), 19)
        self.assertEqual(p["conv_fc_weights"], 268336)
        self.assertEqual(p["conv_fc_macs"], 40551040)

    def test_given_conv_and_addresses(self):
        y, rows = conv_trace()
        self.assertEqual(y, EXPECTED)
        self.assertEqual([r["x_addr"] for r in rows[:9]], [0, 1, 2, 4, 5, 6, 8, 9, 10])
        self.assertEqual(len(rows), 36)

    def test_signed_and_last_term(self):
        rng = random.Random(20261102)
        for _ in range(30):
            x = [[rng.randrange(-128, 128) for _ in range(4)] for _ in range(4)]
            w = [[rng.randrange(-128, 128) for _ in range(3)] for _ in range(3)]
            y, _ = conv_trace(x, w)
            # Distinct flattened-window implementation, including nonzero last products.
            expected = [sum(a * b for a, b in zip(
                [x[i + r][j + c] for r in range(3) for c in range(3)],
                sum(w, []))) for i in range(2) for j in range(2)]
            self.assertEqual(y, expected)

    def test_rne_against_exact_rational(self):
        for divisor in (1, 2, 4, 8, 256):
            for value in range(-1001, 1002):
                self.assertEqual(rne_div(value, divisor), round(Fraction(value, divisor)))

    def test_quantization_boundaries_and_add(self):
        self.assertEqual(requantize(-5, 1, 1), -2)
        self.assertEqual(requantize(-7, 1, 1), -4)
        self.assertEqual(requantize(1000, 1, 0), 127)
        self.assertEqual(requantize(-1000, 1, 0), -128)
        self.assertEqual(requantize(-20, 1, 0, zero_point=5, relu=True), 5)
        self.assertEqual(aligned_add(8, 4, 1, 2, 0), 16)
        self.assertEqual(multiplier_shift(0.3, shift=8), (77, 8))
        with self.assertRaises(ValueError):
            rne_div(1, 0)


if __name__ == "__main__":
    unittest.main()
