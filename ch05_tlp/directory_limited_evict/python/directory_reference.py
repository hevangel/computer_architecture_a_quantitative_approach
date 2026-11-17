"""Reference for an eight-node, one-line-per-node MSI teaching directory."""

class Directory:
    def __init__(self, mode):
        if mode not in (0, 1, 2): raise ValueError("mode")
        self.mode = mode
        self.cache = [[0, 0, 0] for _ in range(8)]  # state, block, value
        self.state = [0] * 4
        self.memory = [160 + i for i in range(4)]
        self.last = self.memory.copy()
        self.owner = [0] * 4
        self.sharers = [set() for _ in range(4)]  # node IDs or coarse group IDs
        self.overflow = [False] * 4
        self.inv = self.puts = self.putm = self.fetch = 0

    def targets(self, block):
        if self.mode == 1 and self.overflow[block]: return set(range(8))
        if self.mode == 2:
            return {node for node in range(8) if node // 2 in self.sharers[block]}
        return set(self.sharers[block])

    def clear(self, block):
        self.sharers[block].clear(); self.overflow[block] = False

    def add(self, block, node):
        if self.mode == 2: self.sharers[block].add(node // 2)
        elif self.mode == 0: self.sharers[block].add(node)
        elif not self.overflow[block] and node not in self.sharers[block]:
            if len(self.sharers[block]) < 2: self.sharers[block].add(node)
            else: self.overflow[block] = True

    def access(self, node, block, write, value):
        state, oldblock, oldvalue = self.cache[node]
        if state and oldblock == block and (not write or state == 2):
            if write:
                self.cache[node][2] = value; self.last[block] = value
            result = self.cache[node][2]
        else:
            if state and oldblock != block:
                if state == 2:
                    self.memory[oldblock] = oldvalue; self.state[oldblock] = 0
                    self.putm += 1; self.clear(oldblock)
                else:
                    self.puts += 1
                    if self.mode == 0 or (self.mode == 1 and not self.overflow[oldblock]):
                        self.sharers[oldblock].discard(node)
                        if not self.sharers[oldblock]: self.state[oldblock] = 0
            if not write:
                if self.state[block] == 2:
                    owner = self.owner[block]
                    result = self.cache[owner][2]; self.memory[block] = result
                    self.cache[owner][0] = 1; self.fetch += 1
                    self.clear(block); self.add(block, owner); self.add(block, node)
                else:
                    result = self.memory[block]; self.add(block, node)
                self.state[block] = 1; self.cache[node] = [1, block, result]
            else:
                if self.state[block] == 2:
                    owner = self.owner[block]
                    self.memory[block] = self.cache[owner][2]
                    self.cache[owner][0] = 0; self.fetch += 1
                elif self.state[block] == 1:
                    recipients = self.targets(block) - {node}; self.inv += len(recipients)
                    for other in recipients:
                        if self.cache[other][0] and self.cache[other][1] == block:
                            self.cache[other][0] = 0
                self.cache[node] = [2, block, value]; self.state[block] = 2
                self.owner[block] = node; self.clear(block); self.last[block] = value; result = value
        self.check_invariants()
        return result

    def check_invariants(self):
        for block in range(4):
            copies = [i for i, (s, b, _) in enumerate(self.cache) if s and b == block]
            if self.state[block] == 0:
                assert not copies and self.memory[block] == self.last[block]
            elif self.state[block] == 1:
                assert all(self.cache[i][0] == 1 and self.cache[i][2] == self.memory[block] for i in copies)
                assert set(copies) <= self.targets(block) and self.memory[block] == self.last[block]
            else:
                assert copies == [self.owner[block]] and self.cache[copies[0]][0] == 2
                assert self.cache[copies[0]][2] == self.last[block]
