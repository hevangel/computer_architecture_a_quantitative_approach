"""Small classic MIPS64 encoded-instruction model with branch delay slots.

Supports LD, SD, DADDU, DSUBU, DMULT, MFLO, SLT, BEQ, NOP and BREAK only.
Memory keys are byte addresses of aligned 64-bit words. This is neither a full
MIPS64 implementation nor a cycle-accurate model.
"""

MASK = (1 << 64) - 1
BREAK = 0x0000000d
NOP = 0


def _reg(value):
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value < 32:
        raise ValueError("register index must be 0..31")
    return value


def _imm(value):
    if isinstance(value, bool) or not isinstance(value, int) or not -32768 <= value <= 32767:
        raise ValueError("immediate must be a signed 16-bit integer")
    return value & 0xffff


def _i(opcode, rt, rs, immediate):
    return (opcode << 26) | (_reg(rs) << 21) | (_reg(rt) << 16) | _imm(immediate)


def ld(rt, rs, offset):
    return _i(0x37, rt, rs, offset)


def sd(rt, rs, offset):
    return _i(0x3f, rt, rs, offset)


def r_type(op, rd, rs, rt):
    funct = {"daddu": 0x2d, "dsubu": 0x2f, "slt": 0x2a}.get(op)
    if funct is None:
        raise ValueError("unknown operation")
    return (_reg(rs) << 21) | (_reg(rt) << 16) | (_reg(rd) << 11) | funct


def dmult(rs, rt):
    return (_reg(rs) << 21) | (_reg(rt) << 16) | 0x1c


def mflo(rd):
    return (_reg(rd) << 11) | 0x12


def beq(rs, rt, offset_words):
    """Branch offset is signed words relative to PC+4, after the delay slot."""
    return _i(4, rt, rs, offset_words)



def addition_program():
    """Compute word[2] = word[0] + word[1] with 64-bit wraparound."""
    return [ld(1, 0, 0), ld(2, 0, 8), r_type("daddu", 3, 1, 2), sd(3, 0, 16), BREAK]

def expression_program():
    return [ld(1, 0, 0), ld(2, 0, 8), r_type("daddu", 1, 1, 2), ld(2, 0, 16),
            ld(3, 0, 24), r_type("dsubu", 2, 2, 3), dmult(1, 2), mflo(1), sd(1, 0, 32), BREAK]


def sort_program(length):
    """Unrolled signed bubble sort, using a NOP in every branch delay slot."""
    if isinstance(length, bool) or not isinstance(length, int) or not 0 <= length <= 4096:
        raise ValueError("length must be an integer from 0 to 4096")
    code = []
    for end in range(length - 1, 0, -1):
        for left in range(end):
            a, b = 8 * left, 8 * (left + 1)
            code += [ld(1, 0, a), ld(2, 0, b), r_type("slt", 3, 2, 1),
                     beq(3, 0, 3), NOP, sd(2, 0, a), sd(1, 0, b)]
    return code + [BREAK]


def _signed(value, bits):
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def execute(program, initial_memory, max_instructions=100000):
    """Execute code and report static/dynamic instruction and data traffic.

    EBREAK equivalent BREAK terminates and is counted. Branch delay slots always
    execute; a branch or BREAK in a delay slot is rejected. Register 0 remains
    zero. Uninitialized aligned memory reads zero. Memory values are 64-bit bit
    patterns; SLT and DMULT interpret inputs as signed. No traps or timing modeled.
    """
    code = list(program)
    if not code or any(isinstance(w, bool) or not isinstance(w, int) or not 0 <= w <= 0xffffffff for w in code):
        raise ValueError("program must contain 32-bit instruction words")
    if isinstance(max_instructions, bool) or not isinstance(max_instructions, int) or max_instructions <= 0:
        raise ValueError("max_instructions must be positive")
    memory = dict(initial_memory)
    if any(isinstance(a, bool) or not isinstance(a, int) or not 0 <= a <= MASK or a % 8 for a in memory):
        raise ValueError("memory addresses must be aligned 64-bit byte addresses")
    if any(isinstance(v, bool) or not isinstance(v, int) for v in memory.values()):
        raise ValueError("memory values must be integers")
    memory = {a: v & MASK for a, v in memory.items()}
    registers = [0] * 32
    pc = steps = reads = writes = lo = hi = 0
    pending = None
    while True:
        if pc % 4 or not 0 <= pc < len(code) * 4:
            raise ValueError("misaligned or out-of-range program counter")
        if steps >= max_instructions:
            raise ValueError("instruction limit exceeded")
        insn = code[pc // 4]
        steps += 1
        if insn == BREAK:
            if pending is not None:
                raise ValueError("BREAK in branch delay slot")
            break
        opcode, rs, rt, rd, shamt, funct = ((insn >> 26) & 63, (insn >> 21) & 31,
                                          (insn >> 16) & 31, (insn >> 11) & 31,
                                          (insn >> 6) & 31, insn & 63)
        old_pending = pending
        pending = None
        next_pc = pc + 4
        if opcode in (0x37, 0x3f):
            address = (registers[rs] + _signed(insn & 0xffff, 16)) & MASK
            if address % 8:
                raise ValueError("misaligned data access")
            if opcode == 0x37:
                if rt:
                    registers[rt] = memory.get(address, 0)
                reads += 8
            else:
                memory[address] = registers[rt]
                writes += 8
        elif insn == NOP:
            pass
        elif opcode == 0 and shamt == 0 and funct in (0x2d, 0x2f, 0x2a):
            a, b = registers[rs], registers[rt]
            result = a + b if funct == 0x2d else a - b if funct == 0x2f else int(_signed(a, 64) < _signed(b, 64))
            if rd:
                registers[rd] = result & MASK
        elif opcode == 0 and funct == 0x1c and rd == 0 and shamt == 0:
            product = (_signed(registers[rs], 64) * _signed(registers[rt], 64)) & ((1 << 128) - 1)
            lo, hi = product & MASK, product >> 64
        elif opcode == 0 and funct == 0x12 and rs == 0 and rt == 0 and shamt == 0:
            if rd:
                registers[rd] = lo
        elif opcode == 4:
            if old_pending is not None:
                raise ValueError("branch in branch delay slot")
            target = pc + 4 + (_signed(insn & 0xffff, 16) * 4)
            pending = target if registers[rs] == registers[rt] else pc + 8
        else:
            raise ValueError(f"unsupported instruction 0x{insn:08x}")
        pc = old_pending if old_pending is not None else next_pc
    return {"memory": memory, "registers": registers, "hi": hi, "lo": lo,
            "instructions": steps, "static_code_bytes": 4 * len(code),
            "dynamic_code_bytes": 4 * steps, "data_read_bytes": reads, "data_write_bytes": writes}
