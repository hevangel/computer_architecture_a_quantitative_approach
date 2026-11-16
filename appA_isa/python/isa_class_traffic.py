"""Execute two kernels on four deliberately small teaching ISA classes.

Instructions and their byte lengths are synthetic, not actual DLX, MIPS, or
RISC-V encodings. Memory contains unbounded Python integers at word addresses;
every data-memory or memory-backed-stack access transfers one four-byte word.
Instruction fetch is counted separately from data traffic.
"""

WORD_BYTES = 4
STYLES = ("stack", "accumulator", "register_memory", "load_store")

# Sizes are explicit modeling assumptions, not instructions assembled to bytes.
SIZES = {
    "stack": {"load": 3, "store": 3, "add": 1, "sub": 1, "mul": 1, "cmp": 1, "jle": 3, "halt": 1},
    "accumulator": {"load": 3, "store": 3, "add": 3, "sub": 3, "mul": 3, "cmp": 3, "jle": 3, "halt": 1},
    "register_memory": {"load": 4, "store": 4, "add": 4, "sub": 4, "mul": 4, "cmp": 4, "jle": 4, "halt": 1},
    "load_store": {"load": 4, "store": 4, "add": 4, "sub": 4, "mul": 4, "cmp": 4, "jle": 4, "halt": 4},
}


def expression_program(style):
    """Program computing memory[4] = (memory[0]+memory[1])*(memory[2]-memory[3])."""
    if style == "stack":
        return [("load", 0), ("load", 1), ("add",), ("load", 2), ("load", 3),
                ("sub",), ("mul",), ("store", 4), ("halt",)]
    if style == "accumulator":
        return [("load", 0), ("add", 1), ("store", 5), ("load", 2), ("sub", 3),
                ("mul", 5), ("store", 4), ("halt",)]
    if style == "register_memory":
        return [("load", 0, 0), ("add", 0, 1), ("store", 0, 5), ("load", 1, 2),
                ("sub", 1, 3), ("mul", 1, 5), ("store", 1, 4), ("halt",)]
    if style == "load_store":
        return [("load", 0, 0), ("load", 1, 1), ("add", 0, 0, 1), ("load", 1, 2),
                ("load", 2, 3), ("sub", 1, 1, 2), ("mul", 0, 0, 1),
                ("store", 0, 4), ("halt",)]
    raise ValueError("unknown ISA style")


def sort_program(style, length):
    """Generate an unrolled adjacent-comparison bubble sort over addresses [0, length)."""
    if style not in STYLES:
        raise ValueError("unknown ISA style")
    if isinstance(length, bool) or not isinstance(length, int) or length < 0:
        raise ValueError("length must be a nonnegative integer")
    program = []
    for end in range(length - 1, 0, -1):
        for left in range(end):
            right = left + 1
            if style == "stack":
                program += [("load", left), ("load", right), ("cmp",)]
                swap = [("load", left), ("load", right), ("store", left), ("store", right)]
            elif style == "accumulator":
                program += [("load", left), ("cmp", right)]
                swap = [("load", left), ("store", length), ("load", right), ("store", left),
                        ("load", length), ("store", right)]
            elif style == "register_memory":
                program += [("load", 0, left), ("cmp", 0, right)]
                swap = [("load", 1, right), ("store", 1, left), ("store", 0, right)]
            else:
                program += [("load", 0, left), ("load", 1, right), ("cmp", 0, 1)]
                swap = [("store", 1, left), ("store", 0, right)]
            # Branch target is the instruction after this swap block.
            program.append(("jle", len(program) + 1 + len(swap)))
            program.extend(swap)
    return program + [("halt",)]


def execute(style, program, initial_memory, max_instructions=100000):
    """Execute program and return memory and static/dynamic traffic counters.

    Branch targets are instruction indices. Undefined data words read as zero;
    stack underflow, invalid register indices, bad opcodes and bad branches fail.
    Stack reads/writes are counted as data traffic, so they can be compared to
    explicit memory operations instead of treating an infinite stack as free.
    """
    if style not in STYLES:
        raise ValueError("unknown ISA style")
    if not isinstance(max_instructions, int) or max_instructions <= 0:
        raise ValueError("max_instructions must be a positive integer")
    code = list(program)
    if not code or any(not instruction or instruction[0] not in SIZES[style] for instruction in code):
        raise ValueError("empty program or invalid opcode")
    memory = dict(initial_memory)
    stack = []
    registers = [0] * 8
    accumulator = 0
    comparison = 0
    pc = steps = dynamic_bytes = reads = writes = 0

    def read(address):
        nonlocal reads
        reads += WORD_BYTES
        return memory.get(address, 0)

    def write(address, value):
        nonlocal writes
        writes += WORD_BYTES
        memory[address] = value

    def pop():
        nonlocal reads
        if not stack:
            raise ValueError("stack underflow")
        reads += WORD_BYTES
        return stack.pop()

    def push(value):
        nonlocal writes
        writes += WORD_BYTES
        stack.append(value)

    def reg(index):
        if isinstance(index, bool) or not isinstance(index, int) or not 0 <= index < len(registers):
            raise ValueError("invalid register")
        return registers[index]

    while True:
        if not 0 <= pc < len(code):
            raise ValueError("program counter outside program")
        if steps >= max_instructions:
            raise ValueError("instruction limit exceeded")
        instruction = code[pc]
        op, args = instruction[0], instruction[1:]
        pc += 1
        steps += 1
        dynamic_bytes += SIZES[style][op]
        if op == "halt":
            break
        if op == "jle":
            if comparison <= 0:
                target = args[0]
                if not isinstance(target, int) or not 0 <= target < len(code):
                    raise ValueError("invalid branch target")
                pc = target
            continue
        if op == "load":
            if style == "stack":
                push(read(args[0]))
            elif style == "accumulator":
                accumulator = read(args[0])
            else:
                reg(args[0])
                registers[args[0]] = read(args[1])
            continue
        if op == "store":
            if style == "stack":
                write(args[0], pop())
            elif style == "accumulator":
                write(args[0], accumulator)
            else:
                write(args[1], reg(args[0]))
            continue
        if style == "stack":
            right, left = pop(), pop()
        elif style == "accumulator":
            left, right = accumulator, read(args[0])
        elif style == "register_memory":
            left, right = reg(args[0]), read(args[1])
        else:
            left, right = (reg(args[0]), reg(args[1])) if op == "cmp" else (reg(args[1]), reg(args[2]))
        if op == "cmp":
            comparison = (left > right) - (left < right)
        else:
            result = {"add": lambda: left + right, "sub": lambda: left - right,
                      "mul": lambda: left * right}[op]()
            if style == "stack":
                push(result)
            elif style == "accumulator":
                accumulator = result
            else:
                destination = args[0]
                reg(destination)
                registers[destination] = result
    return {"memory": memory, "instructions": steps,
            "static_code_bytes": sum(SIZES[style][i[0]] for i in code),
            "dynamic_code_bytes": dynamic_bytes, "data_read_bytes": reads,
            "data_write_bytes": writes}


if __name__ == "__main__":
    import json
    import mips64_traffic as mips
    import rv32im_traffic as rv
    for style in STYLES:
        for name, program, values in (
            ("expression", expression_program(style), [2, 3, 11, 7]),
            ("sort", sort_program(style, 4), [4, 1, 3, 2]),
        ):
            print(json.dumps({"style": style, "kernel": name,
                              **execute(style, program, dict(enumerate(values)))}))
    for name, program, values in (
        ("expression", rv.expression_program(), [2, 3, 11, 7]),
        ("sort", rv.sort_program(4), [4, 1, 3, 2]),
    ):
        print(json.dumps({"style": "rv32im", "kernel": name,
                          **rv.execute(program, {4 * i: value for i, value in enumerate(values)})}))
    for name, program, values in (
        ("expression", mips.expression_program(), [2, 3, 11, 7]),
        ("sort", mips.sort_program(4), [4, 1, 3, 2]),
    ):
        print(json.dumps({"style": "mips64", "kernel": name,
                          **mips.execute(program, {8 * i: value for i, value in enumerate(values)})}))
