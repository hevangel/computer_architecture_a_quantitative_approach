"""Assemble the two DAXPY schedules and the directed VLIW feature programs."""
from pathlib import Path

ADD, _, MUL, ADDI, LD, ST, BNEZ, JMP, LDS, LDA, CHKS, CHKA, PSET, ROTBR, HALT = range(1,16)

def op(code, rd=0, ra=0, rb=0, imm=0, pred=0, negate=False):
    return (code<<28)|(rd<<24)|(ra<<20)|(rb<<16)|(pred<<13)|(int(negate)<<12)|(imm & 0xfff)

def bundle(alu0=0, alu1=0, memory=0, control=0):
    return sum(word<<(32*i) for i,word in enumerate((alu0,alu1,memory,control)))

def baseline():
    return [
        bundle(op(ADDI,2,imm=64),op(ADDI,7,imm=3)), bundle(op(ADDI,8,imm=4)),
        bundle(op(ADDI,8,8,imm=-1)|0xf000,memory=op(LD,3,1)),
        bundle(memory=op(LD,9,1,imm=4)),
        bundle(op(MUL,5,3,7),op(ADDI,1,1,imm=8),op(LD,4,2)),
        bundle(op(MUL,11,9,7),memory=op(LD,10,2,imm=4)),
        bundle(op(ADD,6,5,4)),
        bundle(op(ADD,12,11,10),memory=op(ST,ra=2,rb=6)),
        bundle(op(ADDI,2,2,imm=8),memory=op(ST,ra=2,rb=12,imm=4),control=op(BNEZ,ra=8,imm=2)),
        bundle(control=op(HALT)),
    ]

def pipeline(count):
    return [
        bundle(op(ADDI,2,imm=64),op(ADDI,7,imm=3)), bundle(op(ADDI,5,imm=count)),
        bundle(op(ADDI,1,1,imm=4),memory=op(LD,8,1)),
        bundle(op(ADDI,2,2,imm=4),op(ADDI,5,5,imm=-1),op(LD,9,2)),
        bundle(op(MUL,10,8,7),control=op(ROTBR,ra=5,imm=6)),
        bundle(control=op(JMP,imm=9)),
        bundle(op(ADD,15,14,13),op(ADDI,1,1,imm=4),op(LD,8,1)),
        bundle(op(ADDI,2,2,imm=4),op(ADDI,5,5,imm=-1),op(LD,9,2)),
        bundle(op(MUL,10,8,7),memory=op(ST,ra=2,rb=15,imm=-8),control=op(ROTBR,ra=5,imm=6)),
        bundle(op(ADD,15,14,13)),
        bundle(memory=op(ST,ra=2,rb=15,imm=-4)),
        bundle(control=op(HALT)),
    ]

def speculative(taken):
    return [
        bundle(op(PSET,1,imm=int(not taken)),op(ADDI,1,imm=123)),
        bundle(memory=op(LDS,3,imm=256)),
        bundle(op(ADDI,6,imm=7,pred=1,negate=taken)),
        bundle(op(ADD,4,3)),
        bundle(op(ADDI,2,imm=41,pred=1),
               memory=op(ST,rb=1,imm=100,pred=1,negate=taken),
               control=op(CHKS,ra=4,pred=1)),
        bundle(op(ADDI,5,imm=99),control=op(HALT)),
    ]

def advanced():
    return [
        bundle(op(ADDI,1,imm=42),memory=op(LDA,3)),
        bundle(memory=op(ST,rb=1,imm=20)),
        bundle(control=op(CHKA,ra=3,imm=15)), # Disjoint store leaves entry valid.
        bundle(memory=op(ST,rb=1)),
        bundle(control=op(CHKA,ra=3,imm=6)), # Overlap invalidates it.
        bundle(control=op(HALT)),
        bundle(memory=op(LDA,4,imm=4)),
        bundle(memory=op(LDA,5,imm=8)),
        bundle(memory=op(LDA,6,imm=12)),
        bundle(memory=op(LDA,7,imm=16)),
        bundle(memory=op(LDA,8,imm=20)),
        bundle(control=op(CHKA,ra=4,imm=13)), # Fifth new entry evicts the oldest.
        bundle(control=op(HALT)),
        bundle(op(ADDI,2,imm=99),control=op(HALT)),
        bundle(),
        bundle(op(ADDI,2,imm=55),control=op(HALT)),
    ]

def main():
    programs=[baseline(),pipeline(8),pipeline(1),speculative(False),speculative(True),advanced()]
    path=Path(__file__).resolve().parents[1]/"programs.hex"
    path.write_text("".join(f"{word:032x}\n" for program in programs for word in program+[0]*(16-len(program))),
                    encoding="ascii",newline="\n")

if __name__=="__main__":
    main()
