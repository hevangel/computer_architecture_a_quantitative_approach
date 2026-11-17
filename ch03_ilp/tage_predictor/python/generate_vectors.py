"""Generate deterministic cycle-by-cycle vectors using the Python reference."""
from pathlib import Path
import random
import sys
from tage_reference import Predictor


def generate():
    # The circular sequence has at least one six-bit history followed by
    # both outcomes, so a six-bit history alone cannot predict it perfectly.
    sequence = [(0x6108 >> i) & 1 for i in range(16)]
    successors = {}
    for i, value in enumerate(sequence):
        key = tuple(sequence[(i-j) % 16] for j in range(1, 7))
        successors.setdefault(key, set()).add(value)
    assert any(len(values) > 1 for values in successors.values())
    predictor = Predictor()
    rng = random.Random(1367)
    output = []
    tage_errors = gshare_errors = 0
    for i in range(7024):
        if i < 6000:
            pc = 0x100
            taken = bool((0x6108 >> (i % 16)) & 1)
        else:
            pc = rng.randrange(256) * 4
            taken = bool(rng.getrandbits(1))
        prediction, gshare, provider = predictor.update(pc, taken)
        bits = int(taken) | (int(prediction) << 1) | (int(gshare) << 2) | ((provider + 1) << 3)
        output.append(f"{pc:04x} {bits:02x}")
        if 4000 <= i < 6000:
            tage_errors += prediction != taken
            gshare_errors += gshare != taken
    assert (tage_errors, gshare_errors) == (0, 125)
    return "\n".join(output) + "\n"


if __name__ == "__main__":
    path = Path(__file__).resolve().parent.parent / "golden.txt"
    content = generate()
    if "--check" in sys.argv:
        if path.read_text(encoding="ascii") != content:
            raise SystemExit("golden vectors differ")
        print("golden vectors match; steady-state errors TAGE=0 gshare=125")
    else:
        path.write_text(content, encoding="ascii", newline="\n")
