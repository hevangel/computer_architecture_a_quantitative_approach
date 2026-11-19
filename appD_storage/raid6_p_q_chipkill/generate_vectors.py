from pathlib import Path
import random
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))
from raid6_chipkill_ref import encode


def packed(values, width):
    return sum(value << (i * width) for i, value in enumerate(values))


def generate():
    rng = random.Random(44)
    words = [0, 0x08040201, 0x110180ff, 0xffffffff]
    words += [rng.getrandbits(32) for _ in range(32)]
    return ''.join(f'{word:08x} {packed(encode([(word >> (8*i)) & 255 for i in range(4)], 8, 0x11d), 8):012x} '
                   f'{packed(encode([(word >> (4*i)) & 15 for i in range(8)], 4, 0x13), 4):010x}\n'
                   for word in words)


if __name__ == '__main__':
    path = Path(__file__).with_name('golden.txt')
    if '--check' in sys.argv:
        if path.read_text(encoding='ascii') != generate():
            raise SystemExit('golden vectors differ')
        print('golden vectors match')
    else:
        path.write_text(generate(), encoding='ascii', newline='\n')
