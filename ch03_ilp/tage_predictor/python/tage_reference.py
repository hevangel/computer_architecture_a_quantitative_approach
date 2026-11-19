"""Non-speculative small tagged-history predictor and gshare reference."""
LENGTHS = (2, 6, 18)


def saturate(value, maximum, up):
    return min(value + 1, maximum) if up else max(value - 1, 0)


class Predictor:
    def __init__(self):
        self.history = 0
        self.base = [1] * 16
        self.gshare = [1] * 16
        self.tables = [[None] * 16 for _ in LENGTHS]

    def lookup(self, pc):
        base = self.base[(pc >> 2) & 15] >= 2
        entries = []
        for length, table in zip(LENGTHS, self.tables):
            h = self.history & ((1 << length) - 1)
            index = ((pc >> 2) ^ h) & 15
            tag = ((pc >> 2) ^ h ^ (h >> 8) ^ (h >> 16)) & 255
            entry = table[index]
            entries.append((index, tag, entry if entry is not None and entry[0] == tag else None))
        matches = [i for i, (_, _, entry) in enumerate(entries) if entry is not None]
        provider = matches[-1] if matches else -1
        alternate = entries[matches[-2]][2][1] >= 4 if len(matches) > 1 else base
        prediction = entries[provider][2][1] >= 4 if provider >= 0 else base
        gshare = self.gshare[((pc >> 2) ^ self.history) & 15] >= 2
        return prediction, gshare, provider, alternate, entries

    def update(self, pc, taken):
        prediction, gshare, provider, alternate, entries = self.lookup(pc)
        bi = (pc >> 2) & 15
        gi = ((pc >> 2) ^ self.history) & 15
        self.base[bi] = saturate(self.base[bi], 3, taken)
        self.gshare[gi] = saturate(self.gshare[gi], 3, taken)
        if provider >= 0:
            index, tag, entry = entries[provider]
            useful = entry[2]
            if prediction != alternate:
                useful = saturate(useful, 3, prediction == taken)
            self.tables[provider][index] = (tag, saturate(entry[1], 7, taken), useful)
        if prediction != taken:
            eligible = list(range(provider + 1, len(LENGTHS)))
            allocate = next((i for i in eligible if self.tables[i][entries[i][0]] is None or
                             self.tables[i][entries[i][0]][2] == 0), None)
            if allocate is not None:
                index, tag, _ = entries[allocate]
                self.tables[allocate][index] = (tag, 4 if taken else 3, 0)
            else:
                for i in eligible:
                    index, _, _ = entries[i]
                    old = self.tables[i][index]
                    if old is not None:
                        self.tables[i][index] = (old[0], old[1], max(old[2] - 1, 0))
        self.history = ((self.history << 1) | int(taken)) & ((1 << 18) - 1)
        return prediction, gshare, provider
