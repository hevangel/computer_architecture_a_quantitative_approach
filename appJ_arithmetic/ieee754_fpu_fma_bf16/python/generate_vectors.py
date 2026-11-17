"""Generate deterministic hardware vectors using the exact rational oracle."""
from pathlib import Path
from random import Random
from fp_reference import add, multiply, fma, fma_low_precision, MODES

def vectors():
    rng = Random(0x754f00d)
    edges = [0,0x80000000,1,0x80000001,0x007fffff,0x00800000,
             0x3f800000,0xbf800000,0x3f800001,0x3f7ffffe,0x7f7fffff,
             0xff7fffff,0x7f800000,0xff800000,0x7fc12345,0x7f800001]
    for op in range(3):
        for mode in range(4):
            for a in edges:
                for b in edges:
                    c = edges[(a ^ b) % len(edges)]
                    yield op,0,mode,a,b,c,0,0
    for n in range(2500):
        op = n % 3
        fmt = rng.randrange(4) if op==2 else 0
        mode = rng.randrange(4)
        if fmt==0:
            a,b,c = (rng.getrandbits(32) for _ in range(3))
            sa=sb=0
        else:
            a,b = rng.getrandbits(16 if fmt==1 else 8),rng.getrandbits(16 if fmt==1 else 8)
            c = rng.getrandbits(32)
            sa,sb = rng.randrange(-128,128),rng.randrange(-128,128)
        yield op,fmt,mode,a,b,c,sa,sb
    for mode in range(4):
        for fmt in (1,2,3):
            vals = [0,1,0x7f,0x80,0xff] if fmt != 1 else [0,1,0x3f80,0x7f7f,0x7f80,0x7f81,0x8000]
            for a in vals:
                for b in vals:
                    for sa,sb in ((-128,-128),(127,127),(-128,127),(0,0)):
                        yield 2,fmt,mode,a,b,0x3f800000,sa,sb

def main():
    out=[]
    for op,fmt,mode,a,b,c,sa,sb in vectors():
        if op==0: r=add(a,b,MODES[mode])
        elif op==1: r=multiply(a,b,MODES[mode])
        elif fmt==0: r=fma(a,b,c,MODES[mode])
        else: r=fma_low_precision(a,b,c,('','bf16','e5m2','e4m3fn')[fmt],sa,sb,MODES[mode])
        out.append(f'{op} {fmt} {mode} {a:08x} {b:08x} {c:08x} {sa} {sb} {r.bits:08x} {r.flags:02x}\n')
    p=Path(__file__).with_name('fp_vectors.txt')
    p.write_text(''.join(out),encoding='ascii',newline='\n')
    print(f'{len(out)} vectors written to {p}')
if __name__=='__main__': main()
