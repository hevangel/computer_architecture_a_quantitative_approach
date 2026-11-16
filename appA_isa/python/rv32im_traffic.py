"""A small RV32IM binary encoder/interpreter for the ISA traffic kernels.

Only LW, SW, ADD, SUB, MUL, BGE and EBREAK are implemented. Programs and memory
are separate: memory keys are byte addresses of aligned 32-bit words. This is a
functional teaching model, not a full RISC-V implementation or timing model.
"""

MASK = 0xffffffff
EBREAK = 0x00100073


def _reg(value):
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value < 32:
        raise ValueError("register index must be 0..31")
    return value


def _immediate(value, bits, alignment=1):
    if isinstance(value, bool) or not isinstance(value, int) or not -(1 << (bits - 1)) <= value < (1 << (bits - 1)) or value % alignment:
        raise ValueError("immediate out of range or misaligned")
    return value & ((1 << bits) - 1)


def lw(rd, rs1, offset):
    imm = _immediate(offset, 12)
    return (imm << 20) | (_reg(rs1) << 15) | (2 << 12) | (_reg(rd) << 7) | 0x03


def sw(rs2, rs1, offset):
    imm = _immediate(offset, 12)
    return ((imm >> 5) << 25) | (_reg(rs2) << 20) | (_reg(rs1) << 15) | (2 << 12) | ((imm & 31) << 7) | 0x23


def alu(op, rd, rs1, rs2):
    funct7 = {"add": 0, "sub": 0x20, "mul": 1}.get(op)
    if funct7 is None:
        raise ValueError("unknown ALU operation")
    return (funct7 << 25) | (_reg(rs2) << 20) | (_reg(rs1) << 15) | (_reg(rd) << 7) | 0x33


def bge(rs1, rs2, offset):
    imm = _immediate(offset, 13, 2)
    return (((imm >> 12) & 1) << 31) | (((imm >> 5) & 63) << 25) | (_reg(rs2) << 20) | (_reg(rs1) << 15) | (5 << 12) | (((imm >> 1) & 15) << 8) | (((imm >> 11) & 1) << 7) | 0x63


def expression_program():
    """Compute word[4] = (word[0]+word[1])*(word[2]-word[3]), modulo 2^32."""
    return [lw(1, 0, 0), lw(2, 0, 4), alu("add", 1, 1, 2), lw(2, 0, 8),
            lw(3, 0, 12), alu("sub", 2, 2, 3), alu("mul", 1, 1, 2), sw(1, 0, 16), EBREAK]


def sort_program(length):
    """Unrolled signed adjacent-comparison bubble sort starting at byte address 0."""
    if isinstance(length, bool) or not isinstance(length, int) or not 0 <= length <= 512:
        raise ValueError("length must be an integer from 0 to 512")
    code = []
    for end in range(length - 1, 0, -1):
        for left in range(end):
            a, b = 4 * left, 4 * (left + 1)
            code += [lw(1, 0, a), lw(2, 0, b), bge(2, 1, 12), sw(2, 0, a), sw(1, 0, b)]
    return code + [EBREAK]


def _signed(value, bits):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def execute(program, initial_memory, max_instructions=100000):
    """Execute real encoded instructions and report functional results and traffic.

    Only aligned word access is supported. Unknown words read as zero; EBREAK is
    counted and terminates execution. Data memory values are unsigned 32-bit bit
    patterns, with signed interpretation for BGE. No traps or timing are modeled.
    """
    code = list(program)
    if not code or any(isinstance(w, bool) or not isinstance(w, int) or not 0 <= w <= MASK for w in code):
        raise ValueError("program must contain 32-bit instruction words")
    if isinstance(max_instructions, bool) or not isinstance(max_instructions, int) or max_instructions <= 0:
        raise ValueError("max_instructions must be positive")
    memory = dict(initial_memory)
    if any(isinstance(a, bool) or not isinstance(a, int) or not 0 <= a <= MASK or a % 4 for a in memory):
        raise ValueError("memory addresses must be aligned 32-bit byte addresses")
    if any(isinstance(v, bool) or not isinstance(v, int) for v in memory.values()):
        raise ValueError("memory values must be integers")
    memory = {a: v & MASK for a, v in memory.items()}
    registers = [0] * 32
    pc = steps = reads = writes = 0
    while True:
        if pc % 4 or not 0 <= pc < len(code) * 4:
            raise ValueError("misaligned or out-of-range program counter")
        if steps >= max_instructions:
            raise ValueError("instruction limit exceeded")
        insn = code[pc // 4]
        steps += 1
        if insn == EBREAK:
            break
        opcode, rd, f3 = insn & 0x7f, (insn >> 7) & 31, (insn >> 12) & 7
        rs1, rs2, f7 = (insn >> 15) & 31, (insn >> 20) & 31, (insn >> 25) & 127
        next_pc = pc + 4
        if opcode == 3 and f3 == 2:
            address = (registers[rs1] + _signed(insn >> 20, 12)) & MASK
            if address % 4:
                raise ValueError("misaligned load")
            if rd:
                registers[rd] = memory.get(address, 0)
            reads += 4
        elif opcode == 0x23 and f3 == 2:
            immediate = ((insn >> 25) << 5) | ((insn >> 7) & 31)
            address = (registers[rs1] + _signed(immediate, 12)) & MASK
            if address % 4:
                raise ValueError("misaligned store")
            memory[address] = registers[rs2]
            writes += 4
        elif opcode == 0x33 and f3 == 0 and f7 in (0, 0x20, 1):
            a, b = registers[rs1], registers[rs2]
            result = a + b if f7 == 0 else a - b if f7 == 0x20 else a * b
            if rd:
                registers[rd] = result & MASK
        elif opcode == 0x63 and f3 == 5:
            immediate = (((insn >> 31) & 1) << 12) | (((insn >> 7) & 1) << 11) | (((insn >> 25) & 63) << 5) | (((insn >> 8) & 15) << 1)
            if _signed(registers[rs1], 32) >= _signed(registers[rs2], 32):
                next_pc = pc + _signed(immediate, 13)
        else:
            raise ValueError(f"unsupported instruction 0x{insn:08x}")
        pc = next_pc
    return {"memory": memory, "registers": registers, "instructions": steps,
            "static_code_bytes": 4 * len(code), "dynamic_code_bytes": 4 * steps,
            "data_read_bytes": reads, "data_write_bytes": writes}
