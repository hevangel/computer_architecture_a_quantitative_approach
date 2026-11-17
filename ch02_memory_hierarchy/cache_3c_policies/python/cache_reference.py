"""Independent finite-address cache and 3C reference for the RTL traces."""
class Cache:
    def __init__(self, sets, ways, policy):
        if sets < 1 or not 1 <= ways <= 4 or policy not in ("LRU", "FIFO", "RANDOM", "PLRU"):
            raise ValueError("unsupported configuration")
        self.sets, self.ways, self.policy = sets, ways, policy
        self.lines = [[None] * ways for _ in range(sets)]
        self.order = [[] for _ in range(sets)]
        self.bits = [[0, 0, 0] for _ in range(sets)]
        self.shadow, self.seen = [], set()
        self.lfsr = 1
        self.counts = [0, 0, 0]  # compulsory, capacity, conflict/policy

    def access(self, address):
        if not 0 <= address < 256:
            raise ValueError("address must be an 8-bit block number")
        group = address % self.sets
        lines, order = self.lines[group], self.order[group]
        hit = address in lines
        if not hit:
            category = 0 if address not in self.seen else (1 if address not in self.shadow else 2)
            self.counts[category] += 1
            if None in lines:
                way = lines.index(None)
            elif self.policy in ("LRU", "FIFO"):
                way = order.pop(0)
            elif self.policy == "RANDOM":
                way = self.lfsr % self.ways
                order.remove(way)
            else:
                root, left, right = self.bits[group]
                way = (0 if self.ways == 1 else left) if self.ways <= 2 else (left if root == 0 else 2 + right)
                way = min(way, self.ways - 1)
                order.remove(way)
            lines[way] = address
            order.append(way)
            if self.policy == "RANDOM":
                bit = ((self.lfsr >> 7) ^ (self.lfsr >> 5) ^ (self.lfsr >> 4) ^ (self.lfsr >> 3)) & 1
                self.lfsr = ((self.lfsr << 1) & 255) | bit
        else:
            way = lines.index(address)
            if self.policy == "LRU":
                order.remove(way); order.append(way)
        if way < 2:
            self.bits[group][0] = 1
            self.bits[group][1] = 1 - way
        else:
            self.bits[group][0] = 0
            self.bits[group][2] = 3 - way
        self.seen.add(address)
        if address in self.shadow:
            self.shadow.remove(address)
        elif len(self.shadow) == self.sets * self.ways:
            self.shadow.pop(0)
        self.shadow.append(address)
        return hit


def traces():
    return [[(i % 4) * 4 for i in range(256)],
            [i % 5 for i in range(256)],
            [((i * 13) ^ (i // 3)) % 16 for i in range(256)]]


if __name__ == "__main__":
    for trace in traces():
        row = []
        for sets, ways, policy in [(4,1,"LRU"),(2,2,"LRU"),(1,3,"LRU"),(1,4,"LRU"),
                                   (1,4,"FIFO"),(1,4,"RANDOM"),(1,4,"PLRU")]:
            cache = Cache(sets, ways, policy)
            for address in trace:
                cache.access(address)
            row.append(tuple(cache.counts))
        print(row)
