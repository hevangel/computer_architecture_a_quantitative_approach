"""Generate independent 8x8 Sobel and box results for both edge modes."""
from pathlib import Path
import sys


def generate():
    img = [[(y * 37 + x * 19 + y * x * 3) % 256 for x in range(8)] for y in range(8)]
    kernels = (((-1,0,1),(-2,0,2),(-1,0,1)),
               ((-1,-2,-1),(0,0,0),(1,2,1)),
               ((1,1,1),(1,1,1),(1,1,1)))
    lines=[]
    for wrap in (False,True):
        for kernel in kernels:
            for tile in range(4):
                outputs=[]
                for lane in range(16):
                    y=(tile//2)*4+lane//4; x=(tile%2)*4+lane%4
                    total=0
                    for ky in range(3):
                        for kx in range(3):
                            yy=y+ky-1; xx=x+kx-1
                            yy=yy%8 if wrap else max(0,min(7,yy))
                            xx=xx%8 if wrap else max(0,min(7,xx))
                            total+=img[yy][xx]*kernel[ky][kx]
                    outputs.append(total & 0xffff)
                packed=sum(v<<(16*i) for i,v in enumerate(outputs))
                lines.append(f'{packed:064x}\n')
    for wrap in (False, True):
        for dy, dx in ((-1,0), (1,0), (0,1), (0,-1)):
            for tile in range(4):
                values=[]
                for lane in range(16):
                    y=(tile//2)*4+lane//4+dy; x=(tile%2)*4+lane%4+dx
                    y=y%8 if wrap else max(0,min(7,y))
                    x=x%8 if wrap else max(0,min(7,x))
                    values.append(img[y][x])
                lines.append(f"{sum(v << (16*i) for i,v in enumerate(values)):064x}\n")
    return ''.join(lines)


if __name__ == '__main__':
    p=Path(__file__).with_name('golden.txt')
    if '--check' in sys.argv:
        if p.read_text(encoding='ascii') != generate(): raise SystemExit('golden vectors differ')
        print('golden vectors match')
    else: p.write_text(generate(),encoding='ascii',newline='\n')
