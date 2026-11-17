"""Build exhaustive RV32C-subset expansion vectors from instruction fields.

Unsupported compressed instructions are flagged. The expected RV32I words
are assembled independently from decoded register and integer immediate values.
"""
import argparse
from pathlib import Path


def signed(value, bits):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def branch(rs1, offset):
    value = offset & 0x1fff
    return ((value >> 12) << 31) | (((value >> 5) & 63) << 25) | (rs1 << 15) | (((value >> 1) & 15) << 8) | (((value >> 11) & 1) << 7) | 0x63


def jump(rd, offset):
    value = offset & 0x1fffff
    return ((value >> 20) << 31) | (((value >> 1) & 1023) << 21) | (((value >> 11) & 1) << 20) | (((value >> 12) & 255) << 12) | (rd << 7) | 0x6f


def expand(c):
    quadrant, funct = c & 3, (c >> 13) & 7
    rd, rs2 = (c >> 7) & 31, (c >> 2) & 31
    if quadrant == 0 and funct in (2, 6):
        base, reg = 8 + ((c >> 7) & 7), 8 + ((c >> 2) & 7)
        offset = (((c >> 5) & 1) << 6) | (((c >> 10) & 7) << 3) | (((c >> 6) & 1) << 2)
        if funct == 2:
            return (offset << 20) | (base << 15) | (2 << 12) | (reg << 7) | 3, 0
        return ((offset >> 5) << 25) | (reg << 20) | (base << 15) | (2 << 12) | ((offset & 31) << 7) | 0x23, 0
    if quadrant == 1 and funct == 0:
        immediate = signed((((c >> 12) & 1) << 5) | ((c >> 2) & 31), 6)
        return ((immediate & 0xfff) << 20) | (rd << 15) | (rd << 7) | 0x13, 0
    if quadrant == 1 and funct == 6:
        offset = (((c >> 12) & 1) << 8) | (((c >> 5) & 3) << 6) | (((c >> 2) & 1) << 5) | (((c >> 10) & 3) << 3) | (((c >> 3) & 3) << 1)
        return branch(8 + ((c >> 7) & 7), signed(offset, 9)), 0
    if quadrant == 1 and funct in (1, 5):
        offset = (((c >> 12) & 1) << 11) | (((c >> 8) & 1) << 10) | (((c >> 9) & 3) << 8) | (((c >> 6) & 1) << 7) | (((c >> 7) & 1) << 6) | (((c >> 2) & 1) << 5) | (((c >> 11) & 1) << 4) | (((c >> 3) & 7) << 1)
        return jump(1 if funct == 1 else 0, signed(offset, 12)), 0
    if quadrant == 2 and funct == 4 and rs2:
        rs1 = rd if c & 0x1000 else 0
        return (rs2 << 20) | (rs1 << 15) | (rd << 7) | 0x33, 0
    return 0, 1


def contents():
    # External encoding anchors: LLVM RISC-V MC rvc-valid.s; expected RV32I
    # fields are derived from the instruction operands, not from RTL output.
    assert expand(0x4110) == (0x00052603, 0)  # c.lw a2, 0(a0)
    assert expand(0x1681) == (0xfe068693, 0)  # c.addi a3, -32
    assert expand(0x88a2) == (0x008008b3, 0)  # c.mv a7, s0
    assert expand(0xd281) == (branch(13, -256), 0)
    assert expand(0xb001) == (jump(0, -2048), 0)
    return "".join(f"{c:04x} {word:08x} {illegal}\n" for c in range(65536) if c & 3 != 3
                   for word, illegal in (expand(c),))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    path = Path(__file__).with_name("golden.txt")
    expected = contents()
    if args.check:
        if path.read_text(encoding="ascii") != expected:
            raise SystemExit("golden.txt differs from the reference")
        print("49,152 compressed encodings match the Python reference")
    else:
        path.write_text(expected, encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
