"""Build tile fixtures with exact rational FMA rounding per accumulation step."""
from pathlib import Path
from random import Random
import sys

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[3] / "appJ_arithmetic/ieee754_fpu_fma_bf16/python"))
from fp_reference import fma_low_precision

def packed(values, width):
    return sum(value << (width * index) for index, value in enumerate(values))

def main():
    rng = Random(0x2444)
    encodings = {
        1: ("bf16", [0x3e80, 0x3f00, 0x3f80, 0xbf80, 0x4000, 0xc000, 0x4040]),
        2: ("e5m2", [0x01, 0x34, 0x38, 0x3c, 0xbc, 0x40, 0xc0, 0x42]),
        3: ("e4m3fn", [0x01, 0x28, 0x30, 0x38, 0xb8, 0x40, 0xc0, 0x44]),
    }
    lines = []
    for number in range(30):
        format_code = 1 + number % 3
        fmt, values = encodings[format_code]
        sa, sb = (-18 if number % 5 == 0 else rng.randint(-4, 3)), rng.randint(-4, 3)
        a = rng.choices(values, k=16)
        c = rng.choices([0, 0x3f800000, 0x3f800001, 0xbe800000], k=16)
        b = [0] * 16
        compact = [0] * 8
        metadata = []
        for col in range(4):
            locations = sorted(rng.sample(range(4), 2))
            metadata.extend(locations)
            for slot, k in enumerate(locations):
                b[4*k+col] = compact[4*slot+col] = rng.choice(values)
        d, flags = [], 0
        for row in range(4):
            for col in range(4):
                dense_result = c[4*row+col]
                compact_result = dense_result
                dense_flags = compact_flags = 0
                for k in range(4):
                    result = fma_low_precision(a[4*row+k], b[4*k+col], dense_result, fmt, sa, sb)
                    dense_result = result.bits
                    dense_flags |= result.flags
                for slot in range(2):
                    k = metadata[2*col+slot]
                    result = fma_low_precision(a[4*row+k], compact[4*slot+col], compact_result, fmt, sa, sb)
                    compact_result = result.bits
                    compact_flags |= result.flags
                assert (dense_result, dense_flags) == (compact_result, compact_flags)
                flags |= dense_flags
                d.append(dense_result)
        lines.append(
            f"{format_code} {sa} {sb} {packed(a,16):064x} {packed(c,32):0128x} "
            f"{packed(b,16):064x} {packed(compact,16):032x} {packed(metadata,2):04x} "
            f"{packed(d,32):0128x} {flags:02x}\n"
        )
    (HERE.parents[1] / "vectors.txt").write_text("".join(lines), encoding="ascii", newline="\n")

if __name__ == "__main__":
    main()
