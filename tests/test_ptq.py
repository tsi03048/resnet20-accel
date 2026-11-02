"""Small offline tests; dataset download is not needed."""
import importlib.util
import tempfile
import unittest
from unittest.mock import patch

HAS_TORCH = importlib.util.find_spec("torch") is not None


@unittest.skipUnless(HAS_TORCH, "PyTorch is optional for the first exercise")
class PTQTests(unittest.TestCase):
    def fixture(self):
        import torch
        from torch import nn
        class Block(nn.Module):
            def __init__(self):
                super().__init__()
                self.conv1 = nn.Conv2d(3, 3, 3, padding=1, bias=False)
                self.bn1 = nn.BatchNorm2d(3)
                self.conv2 = nn.Conv2d(3, 3, 3, padding=1, bias=False)
                self.bn2 = nn.BatchNorm2d(3)
                self.shortcut = nn.Sequential()
            def forward(self, x):
                return (self.bn2(self.conv2(self.bn1(self.conv1(x)).relu())) + x).relu()
        class Model(nn.Module):
            def __init__(self):
                super().__init__()
                self.conv1 = nn.Conv2d(3, 3, 3, padding=1, bias=False)
                self.bn1 = nn.BatchNorm2d(3)
                self.layer1, self.layer2, self.layer3 = [nn.Sequential(Block()) for _ in range(3)]
                self.linear = nn.Linear(3, 10)
            def forward(self, x):
                y = self.bn1(self.conv1(x)).relu()
                for layer in (self.layer1, self.layer2, self.layer3):
                    y = layer(y)
                return self.linear(y.mean((2, 3)))
        torch.manual_seed(42)
        torch.set_num_threads(1)
        model = Model().eval()
        train = torch.utils.data.TensorDataset(torch.randn(12, 3, 4, 4), torch.arange(12) % 10)
        test = torch.utils.data.TensorDataset(torch.randn(8, 3, 4, 4), torch.arange(8))
        return model, train, test

    def test_select_on_development_test_once(self):
        from quant import e2_ptq
        from model.common import evaluate
        model, train, test = self.fixture()
        baseline = evaluate(model, test, "cpu")
        seen = []
        def observed(forward, dataset, device):
            seen.append(dataset is test)
            return evaluate(forward, dataset, device)
        with tempfile.TemporaryDirectory() as out, patch.object(e2_ptq, "evaluate", observed):
            report = e2_ptq.run_e2(model, test, train, "cpu", baseline["preds"], baseline["top1"],
                                    out_root=out, calib_n=4, dev_n=4)
        self.assertEqual(sum(seen), 1)
        self.assertTrue(seen[-1])
        self.assertFalse(set(report["calibration"]["indices"]) & set(report["development"]["indices"]))
        self.assertIsNone(report["decision_input"]["recommend_int8"])
        self.assertFalse(report["deployable_integer_reference"])

    def test_bad_folding_stops_before_evaluation(self):
        import torch
        from quant import e2_ptq
        model, train, test = self.fixture()
        original = e2_ptq.forward_folded
        with patch.object(e2_ptq, "forward_folded", lambda p, x: original(p, x) + 1), \
             patch.object(e2_ptq, "evaluate") as evaluate:
            with self.assertRaisesRegex(RuntimeError, "BN folding mismatch"):
                e2_ptq.run_e2(model, test, train, "cpu", torch.zeros(8), 0, calib_n=4, dev_n=4)
            evaluate.assert_not_called()
