"""Generate original signed 16x16 image and 3x3 valid-correlation results."""
import argparse
from pathlib import Path

WIDTH = HEIGHT = 16
KERNEL = [-2, 1, 3, 0, -1, 2, 1, -3, 2]


def vectors():
    pixels = [((i * 73 + (i // WIDTH) * 19 + 17) % 256) - 128 for i in range(WIDTH * HEIGHT)]
    outputs = []
    for row in range(2, HEIGHT):
        for col in range(2, WIDTH):
            outputs.append(sum(pixels[(row - 2 + dy) * WIDTH + col - 2 + dx] * KERNEL[dy * 3 + dx]
                               for dy in range(3) for dx in range(3)))
    return {"pixels.txt": "".join(f"{x}\n" for x in pixels),
            "expected.txt": "".join(f"{x}\n" for x in outputs)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for filename, content in vectors().items():
        path = Path(__file__).with_name(filename)
        if args.check:
            if path.read_text(encoding="ascii") != content:
                raise SystemExit(f"{filename} differs from the Python reference")
        else:
            path.write_text(content, encoding="ascii", newline="\n")
    if args.check:
        print("convolution vectors match the Python reference")


if __name__ == "__main__":
    main()
