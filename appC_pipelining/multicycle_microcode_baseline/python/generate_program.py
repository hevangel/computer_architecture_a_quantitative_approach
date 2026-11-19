from pathlib import Path
def i(op, rd, fn, rs, imm):
    return ((imm&0xfff)<<20)|(rs<<15)|(fn<<12)|(rd<<7)|op
def r(rd, fn, rs1, rs2, sub=False):
    return (int(sub)<<30)|(rs2<<20)|(rs1<<15)|(fn<<12)|(rd<<7)|0x33
def s(rs2, imm):
    return ((imm&0xfe0)<<20)|(rs2<<20)|(2<<12)|((imm&31)<<7)|0x23
def b(fn, rs1, rs2, imm):
    return (((imm>>12)&1)<<31)|((imm&0x7e0)<<20)|(rs2<<20)|(rs1<<15)|(fn<<12)|((imm&0x1e)<<7)|(((imm>>11)&1)<<7)|0x63
def j(rd, imm):
    return (((imm>>20)&1)<<31)|((imm&0x7fe)<<20)|(((imm>>11)&1)<<20)|(imm&0xff000)|(rd<<7)|0x6f
def addi(rd, rs, imm):
    return i(0x13, rd, 0, rs, imm)
# Same 25 instruction encodings as the existing RV32I pipeline test.
code = [addi(1,0,5),addi(2,0,7),r(3,0,1,2),r(4,0,3,1,True),s(3,0),i(3,5,2,0,0),
        r(6,0,5,5),b(0,6,6,8),addi(7,0,99),addi(8,0,1),addi(10,0,10),addi(11,0,0),
        r(11,0,11,10),addi(10,10,-1),b(1,10,0,-8),s(11,4),j(12,8),addi(13,0,77),
        r(14,2,0,11),0x123457b7,addi(16,15,0x678),i(0x13,17,1,14,4),i(0x67,18,0,0,96),
        addi(19,0,55),0x00100073]
if __name__ == '__main__':
    path=Path(__file__).resolve().parents[1]/'program.hex'
    path.write_text(''.join(f'{word:08x}\n' for word in code),encoding='ascii',newline='\n')
