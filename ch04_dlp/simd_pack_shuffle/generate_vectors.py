"""Generate independent saturating-narrowing vectors used by both HDL tests."""
import argparse
from pathlib import Path

INPUTS = [-40000, -32768, -129, -1, 0, 127, 128, 40000]


def clamp(value, bits):
    return max(-(1 << (bits - 1)), min((1 << (bits - 1)) - 1, value))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = Path(__file__).with_name("golden.txt")
    expected = "".join(f"{v} {clamp(v, 16)} {clamp(v, 8)}\n" for v in INPUTS)
    if args.check:
        if path.read_text(encoding="ascii") != expected:
            raise SystemExit("golden.txt does not match the Python reference")
        print("golden.txt matches Python reference")
    else:
        path.write_text(expected, encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
