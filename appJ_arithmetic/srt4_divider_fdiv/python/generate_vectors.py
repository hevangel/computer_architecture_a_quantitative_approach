from pathlib import Path
from random import Random
from srt_reference import divide_trace

def main():
    rng=Random(274)
    edges=[0,1,2,3,0x7fffffff,0x80000000,0xfffffffe,0xffffffff]
    operands=[(4195835,3145727)]
    operands.extend((a,b) for a in edges for b in edges)
    operands.extend((rng.randrange(1,1<<32),rng.randrange(1,1<<32)) for _ in range(512))
    rows=[]
    for a,b in operands:
        if b==0: q,r,m,ex = 0xffffffff,a,0,0
        elif a==0: q,r,m,ex = 0,0,0,0
        else:
            q,r=divmod(a,b)
            ex=a.bit_length()-b.bit_length()
            fraction,_=divide_trace(a,b)
            m=int(fraction*2**(64-ex))
        rows.append(f"{a:08x} {b:08x} {q:08x} {r:08x} {m:018x} {ex}\n")
    p=Path(__file__).resolve().parents[1]/'vectors.txt'
    p.write_text(''.join(rows),encoding='ascii',newline='\n')

if __name__=='__main__':
    main()
