"""Timed two-thread rename/issue reference; no ISA, branches, or stores.

Each thread has an independent in-order rename queue and ROB. Sources are
physical tags captured before destination allocation. Ready instructions issue
in order per thread; execution and retirement may overlap across threads.
"""
from collections import deque
from dataclasses import dataclass
from scheduler_reference import MASK, Instruction, Result

@dataclass
class Entry:
    op: str
    src: int
    dst: int
    old: int
    arch: int
    arg: int
    issued: bool = False
    done: bool = False

class RenameScheduler:
    def __init__(self, programs, memory, mode, nphys=20, rob_size=8,
                 load_latency=7, mul_latency=4, switch_cost=1):
        if len(programs) != 2 or mode not in ('SINGLE', 'COARSE', 'FINE', 'SMT'):
            raise ValueError('two programs and a supported mode are required')
        if nphys < 9 or rob_size < 1 or min(load_latency, mul_latency) < 1 or switch_cost < 0:
            raise ValueError('invalid configuration')
        self.programs = programs
        self.memory = memory
        self.mode = mode
        self.nphys = nphys
        self.rob_size = rob_size
        self.load_latency = load_latency
        self.mul_latency = mul_latency
        self.switch_cost = switch_cost
        self.values = [[0] * nphys for _ in range(2)]
        self.ready = [[True] * nphys for _ in range(2)]
        self.front = [list(range(8)) for _ in range(2)]
        self.committed = [list(range(8)) for _ in range(2)]
        self.free = [set(range(8, nphys)) for _ in range(2)]
        self.rob = [deque(), deque()]
        self.pc = [0, 0]
        self.events = []
        self.cycle = self.issued = self.switched = 0
        self.active = self.rr = self.cooldown = 0
        self.max_live = [0, 0]

    def dispatch(self, t):
        for _ in range(2):
            if self.pc[t] == len(self.programs[t]) or len(self.rob[t]) == self.rob_size or not self.free[t]:
                return
            ins = self.programs[t][self.pc[t]]
            if ins.op not in ('ADD', 'MUL', 'LOAD') or not 0 <= ins.src < 8 or not 0 <= ins.dst < 8:
                raise ValueError('invalid instruction')
            src, old = self.front[t][ins.src], self.front[t][ins.dst]
            dst = min(self.free[t]); self.free[t].remove(dst)
            self.front[t][ins.dst] = dst
            self.ready[t][dst] = False
            self.rob[t].append(Entry(ins.op, src, dst, old, ins.dst, ins.arg))
            self.pc[t] += 1
            self.max_live[t] = max(self.max_live[t], len(self.rob[t]))

    def candidate(self, t, mem_available=True):
        for entry in self.rob[t]:
            if not entry.issued:
                return entry if self.ready[t][entry.src] and (mem_available or entry.op != 'LOAD') else None
        return None

    def done_thread(self, t):
        return self.pc[t] == len(self.programs[t]) and not self.rob[t]

    def issue(self, t, e):
        operand = self.values[t][e.src]
        if e.op == 'ADD':
            value, latency = (operand + e.arg) & MASK, 1
        elif e.op == 'MUL':
            value, latency = (operand * e.arg) & MASK, self.mul_latency
        else:
            address = (operand + e.arg) & MASK
            if address not in self.memory:
                raise ValueError('unmapped load')
            value, latency = self.memory[address] & MASK, self.load_latency
        e.issued = True
        self.events.append((self.cycle + latency, t, e, value))
        self.issued += 1

    def check_invariants(self):
        for t in range(2):
            entries = self.rob[t]
            # A destination remains reserved until its overwriting successor retires.
            held = set(self.committed[t]) | {e.dst for e in entries}
            assert len(self.committed[t]) == len(set(self.committed[t])) == 8
            assert len(held) == 8 + len(entries)
            assert not (held & self.free[t])
            assert held | self.free[t] == set(range(self.nphys))
            mapping = self.committed[t].copy()
            for e in entries:
                assert mapping[e.arch] == e.old
                mapping[e.arch] = e.dst
            assert mapping == self.front[t]

    def tick(self):
        remaining = []
        for due, t, e, value in self.events:
            if due == self.cycle:
                self.values[t][e.dst] = value
                self.ready[t][e.dst] = True
                e.done = True
            else:
                remaining.append((due, t, e, value))
        self.events = remaining
        for t in range(2):
            for _ in range(2):
                if not self.rob[t] or not self.rob[t][0].done:
                    break
                e = self.rob[t].popleft()
                assert self.committed[t][e.arch] == e.old
                self.committed[t][e.arch] = e.dst
                self.free[t].add(e.old)
            self.dispatch(t)
        if self.mode == 'SINGLE' and self.done_thread(0):
            self.active = 1
        switching = False
        if self.mode == 'COARSE' and self.cooldown:
            self.cooldown -= 1
            switching = True
        elif self.mode == 'COARSE' and self.candidate(self.active) is None and not self.done_thread(1-self.active) and self.candidate(1-self.active) is not None:
            self.active = 1-self.active
            self.switched += 1
            if self.switch_cost:
                self.cooldown = self.switch_cost-1
                switching = True
        if not switching:
            chosen = self.cycle % 2 if self.mode == 'FINE' else self.rr if self.mode == 'SMT' else self.active
            mem_available = True
            for _ in range(2):
                e = self.candidate(chosen, mem_available)
                if self.mode == 'SMT' and e is None:
                    chosen = 1-chosen
                    e = self.candidate(chosen, mem_available)
                if e is None:
                    break
                self.issue(chosen, e)
                if e.op == 'LOAD':
                    mem_available = False
                if self.mode == 'SMT':
                    chosen = 1-chosen
            if self.mode == 'SMT':
                self.rr = 1-self.rr
        self.check_invariants()
        self.cycle += 1

    def run(self, limit=10000):
        while not all(self.done_thread(t) for t in range(2)):
            if self.cycle >= limit:
                raise RuntimeError('scheduler did not drain')
            self.tick()
        registers = tuple(tuple(self.values[t][self.committed[t][r]] for r in range(8)) for t in range(2))
        return Result(self.cycle, self.issued, registers, self.switched)
