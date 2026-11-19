"""Create a decoder from exact interval constraints for the two HDLs."""
from pathlib import Path
from srt_reference import select_digit

def thresholds():
    # A constant ROM per decoded divisor, with one digit per row.
    for col in range(16,32):
        encoded=[]
        for row in range(-64,64):
            try: q=select_digit(row,col)
            except ArithmeticError: q=0
            encoded.append(f'{q+2:03b}')
        yield from encoded

def main():
    p=Path(__file__).resolve().parents[1]/'selection.txt'
    p.write_text('\n'.join(thresholds())+'\n', encoding='ascii', newline='\n')

if __name__=='__main__':main()
