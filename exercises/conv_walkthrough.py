"""python -m exercises.conv_walkthrough: B1/연결02의 36 MAC과 주소를 추적한다."""
import csv
import json
from pathlib import Path

X = [[5, 4, 1, 0], [4, 3, 1, 0], [3, 2, 0, 0], [2, 1, 0, 0]]
W = [[1, 0, -1], [1, 0, -1], [1, 0, -1]]
EXPECTED = [10, 9, 8, 6]


def conv_trace(x=X, w=W):
    rows, output = [], []
    for oy in range(2):
        for ox in range(2):
            acc = 0
            for ky in range(3):
                for kx in range(3):
                    xv, wv = x[oy + ky][ox + kx], w[ky][kx]
                    acc += xv * wv
                    rows.append(dict(output=oy * 2 + ox, term=ky * 3 + kx,
                                     x_addr=(oy + ky) * 4 + ox + kx, w_addr=ky * 3 + kx,
                                     x=xv, w=wv, product=xv * wv, psum=acc))
            output.append(acc)
    return output, rows


def main():
    y, rows = conv_trace()
    if y != EXPECTED or len(rows) != 36:
        raise RuntimeError(f"Conv mismatch: {y}")
    root = Path("results/basic")
    root.mkdir(parents=True, exist_ok=True)
    with (root / "conv_trace.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    (root / "conv_result.json").write_text(json.dumps(
        dict(status="PASS", evidence="PYTHON_ARITHMETIC", output=y, macs=len(rows),
             learned_weights=False, fpga_measured=False), indent=2), encoding="utf-8")
    print("Y =", y, "; 36 MAC; PASS")
    print("첫 출력 주소:", [r["x_addr"] for r in rows[:9]])
    print("기록:", root / "conv_trace.csv")


if __name__ == "__main__":
    main()
