# The Five-Stage Pipeline for DLX and MIPS64 (branches resolved in ID)

**Topic:** Appendix C (Pipelining) · **ISA:** DLX in the 1st-2nd editions, MIPS64 in the 3rd-5th ·
**Files:** [`sv/mips_pipeline.sv`](sv/mips_pipeline.sv), [`vhdl/mips_pipeline.vhd`](vhdl/mips_pipeline.vhd)

This is the pipeline that all five of those editions use as their running example. It differs from the
[RISC-V version](../rv32i_pipeline5) in the way the book's Appendix C improves the basic design: **branches and jumps are
resolved in the ID stage**, with a comparator and forwarding path there, cutting the taken-branch penalty from two cycles
to one -- at the price of a new class of data hazard.

## Background

Control hazards are expensive because the pipeline fetches the wrong instructions while a branch is still being decided.
The earlier the branch is resolved, the smaller the penalty:

| Resolved in | Penalty (taken) | Needs |
|-------------|:---------------:|-------|
| EX (RV32I example) | 2 cycles | nothing extra |
| **ID (this example)** | **1 cycle** | a comparator in ID; target adder in ID; operands forwarded *into ID* |

The new hazard: the branch needs its register operands one stage **earlier**, before the ALU result of the instruction just
ahead exists. So the pipeline must stall, or forward from a later stage:

| Producer of the branch operand | What happens |
|--------------------------------|--------------|
| ALU instruction **in EX** (just ahead) | stall 1 cycle, then forward its ALU result from EX/MEM into ID |
| ALU instruction in MEM / WB | forward from EX/MEM, or read the write-through register file |
| **Load in EX** | load-use stall, then the next rule |
| **Load in MEM** | stall 1 more cycle until the data reaches WB, then read the write-through register file |

```
Pipeline CPI = 1 + load-use stalls + branch-operand stalls + taken branches x 1
```

## Design

* **One core, two ISAs** via the `XLEN` generic:

  | | `XLEN = 32` (DLX / MIPS32 flavor) | `XLEN = 64` (MIPS64 flavor) |
  |-|------------------------------------|------------------------------|
  | add / sub | `ADD` `SUB` (funct 20h, 22h) | `DADDU` `DSUBU` (2Dh, 2Fh) |
  | immediate add | `ADDI` (opcode 08h) | `DADDIU` (19h) |
  | shifts | `SLL` `SRL` (00h, 02h) | `DSLL` `DSRL` (38h, 3Ah) |
  | load / store | `LW` `SW` (23h, 2Bh) | `LD` `SD` (37h, 3Fh) |
  | common | `AND OR XOR SLT`, `ANDI ORI LUI`, `BEQ BNE`, `J JAL JR`, `BREAK` | same |

* 32 registers, `r0 = 0`, R/I/J formats, **no delay slot**. Branch offsets count words from PC+4 (MIPS convention);
  `BEQZ`/`BNEZ` from the book are `BEQ`/`BNE` against `r0`. The PC stays 32 bits in both flavors.
* **DLX note.** The 1st/2nd-edition DLX uses the same instruction formats and register conventions as MIPS but assigns its own
  opcode numbers; this example reuses the MIPS numbering for the 32-bit flavor as a stand-in. Check the book's appendix if you
  need the original numbering.
* Forwarding into EX from EX/MEM and MEM/WB; write-through register file; `ebreak`-style `BREAK` halts the machine.
* Counters freeze when `BREAK` retires: cycles, retired, **load-use stalls**, **branch-operand stalls**, taken transfers.

## Verification

The testbench instantiates the core twice (a `mips_harness` wrapper with an `XLEN` generic holds the assembler functions,
memories, program and checks) and runs the same 30-word program with each ISA's own encodings. The program is built to hit every
rule above:

| Words | Code | Exercises |
|-------|------|-----------|
| 0-3 | `addi` `addi` `add` `sub` | forwarding into EX |
| 4-6 | `sw` `lw` `add $6,$5,$5` | **load-use** stall (1) |
| 7-8 | `beq $6,$6,+1` then wrong-path `addi` | operand from the `add` just ahead: **branch stall (1)**, taken |
| 9-14 | 10-iteration loop ending `bne $10,$0,-3` | branch stall *every* iteration (operand from the `addi` ahead), taken 9 times |
| 15-18 | `sw` `jal` wrong-path `slt` | `JAL` link value (`$31 = 68`) |
| 19-21 | `lui` `ori` `sll`/`dsll` | immediates, shifts (`0x12345678`, 16) |
| 22-24 | `lw $20` `addi` `beq $20,$3,+1` | branch operand is a **load in MEM**: stall (1), taken |
| 26-29 | `addi $18,$0,116` `jr $18` wrong-path `addi` `break` | `JR`: stall (1), taken |

Wrong-path instructions (`$7`, `$13`, `$22`, `$19`) must leave no trace. The counters must match the model **exactly**, in both flavors:

```
retired              = 53
load-use stalls      =  1
branch-operand stalls = 13   (beq@7: 1, bne x10: 10, beq@24 after a load: 1, jr: 1)
taken transfers      = 13   (beq@7, bne x9, jal, beq@24, jr)
cycles = 53 + 4 (fill) + 1 + 13 + 13 = 84        CPI = 84 / 53 = 1.58
```

Compare with the RV32I pipeline, whose branches resolve in EX: its program has *no* branch-operand stalls but pays 2 cycles per
taken branch. Which design wins depends on the ratio of taken branches to branches whose operand was produced one instruction
earlier -- measure it by changing the program.

## Run it

```bash
make test T=mips_pipeline
```

## Exercises

1. Add a one-slot **delayed branch** (as MIPS actually did) and measure the CPI with an unfilled versus filled slot.
2. Replace the stall on "operand in EX" by a combinational forward of the ALU output into the ID comparator; discuss the cycle-time cost.
3. Add a **predict-taken** policy with a small BTB (see [`branch_predictor`](../../ch03_ilp/branch_predictor)) to bring the penalty to zero for predicted loops.
4. Add `LW`/`LD` sign- and zero-extending sub-word loads (`LB`, `LBU`, `LH`, `LWU`) to the MIPS64 flavor.
