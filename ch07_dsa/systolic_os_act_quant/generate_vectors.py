"""Generate independent integer GEMM/activation/requantization test vectors."""
import argparse
from pathlib import Path


def contents():
    lines = []
    for case, (mode, shift) in enumerate(((0, 4), (1, 6), (2, 0))):
        a = [((i * 37 + case * 19 + 3) % 256) - 128 for i in range(16)]
        b = [((i * 53 + case * 31 + 29) % 256) - 128 for i in range(16)]
        bias = [((i * 211 + case * 113) % 1801) - 900 for i in range(16)]
        if case == 0:
            bias[0], bias[1] = 2147483647, -2147483648
        lines.append(f"{mode} {shift}\n")
        for i in range(16):
            row, col = divmod(i, 4)
            total = sum(a[row * 4 + k] * b[k * 4 + col] for k in range(4))
            result = total + bias[i]
            if mode in (1, 2):
                result = max(0, result)
            if mode == 2:
                result = min(6, result)
            result = max(-128, min(127, result >> shift))
            lines.append(f"{a[i]} {b[i]} {bias[i]} {total} {result}\n")
    return "".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = Path(__file__).with_name("golden.txt")
    if args.check:
        if path.read_text(encoding="ascii") != contents():
            raise SystemExit("golden.txt differs from the reference")
        print("matrix vectors match the Python reference")
    else:
        path.write_text(contents(), encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
