"""No-dependency graph/shape/MAC inventory for the fixed CIFAR Option A model."""
import json


def build_plan():
    ops = []
    def conv(name, cin, cout, h, w, stride=1):
        oh, ow = h // stride, w // stride
        ops.append(dict(id=len(ops), name=name, op="conv", cin=cin, cout=cout,
                        input_hw=[h, w], output_hw=[oh, ow], stride=stride, padding=1,
                        weights=cout * cin * 9, macs=oh * ow * cout * cin * 9))
        return oh, ow
    h, w = conv("stem", 3, 16, 32, 32)
    cin = 16
    for stage, cout in enumerate((16, 32, 64), 1):
        for block in range(3):
            stride = 2 if stage > 1 and block == 0 else 1
            name = f"L{stage}.{block}"
            h, w = conv(name + ".conv1", cin, cout, h, w, stride)
            conv(name + ".conv2", cout, cout, h, w)
            ops.append(dict(id=len(ops), name=name + ".add_relu", op="add_relu",
                            shortcut="option_a" if stride == 2 else "identity",
                            output_shape=[1, cout, h, w], weights=0, macs=0))
            cin = cout
    ops.append(dict(id=len(ops), name="gap", op="gap", output_shape=[1, 64], weights=0, macs=0))
    ops.append(dict(id=len(ops), name="fc", op="fc", output_shape=[1, 10], weights=640, macs=640))
    return dict(model="ResNet-20 CIFAR Option A", operations=ops,
                conv_fc_weights=sum(o["weights"] for o in ops),
                conv_fc_macs=sum(o["macs"] for o in ops),
                note="Static inventory, not a runtime/exporter or FPGA resource report")


if __name__ == "__main__":
    print(json.dumps(build_plan(), indent=2))
