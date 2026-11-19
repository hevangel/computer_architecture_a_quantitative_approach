"""Independent cycle-level executable specification for the two-way cache.

This uses objects and queues rather than the RTL's parallel arrays.  Inputs and
outputs describe the stable signals immediately before each active clock edge.
The generated trace is consumed by both HDL benches.
"""
from dataclasses import dataclass, field

@dataclass
class Line:
    number: int
    words: list[int]
    dirty: bool = False

@dataclass
class Miss:
    line: int
    state: str
    targets: list[tuple]
    data: list[int] = field(default_factory=list)
    cursor: int = 0
    dirty: bool = False

class Cache:
    def __init__(self):
        self.ways = [[None, None] for _ in range(8)]
        self.lru = [0]*8
        self.misses = [None]*4
        self.wb = []
        self.memory = [(0x5A000000+17*i) & 0xffffffff for i in range(256)]
        self.responses = {}
        self.cycle = 0
        self.busy = 0
        self.hit_response = None
        self.counts = [0, 0, 0, 0]
        self.forwarded = 0
        self.forwarded_blocked = 0
        self.full_stalls = 0
        self.peak_misses = 0

    def step(self, req, allow):
        # Decide all actions from the state at the start of the clock edge.
        mem_ready = not self.busy and allow
        hit = None
        line = (req[1]//4) if req else 0
        setno = line % 8
        if req:
            for way, entry in enumerate(self.ways[setno]):
                if entry is not None and entry.number == line: hit = way
        match = next((i for i,m in enumerate(self.misses) if m and m.line==line), None)
        merge = match if match is not None and self.misses[match].state in ('need','wait') and len(self.misses[match].targets)<4 else None
        free = next((i for i,m in enumerate(self.misses) if m is None), None)
        fill = next((i for i,m in enumerate(self.misses) if m and m.state=='filled'),None)
        install = next((i for i,m in enumerate(self.misses) if m and m.state=='install'),None)
        slot = None
        if install is not None:
            iset = self.misses[install].line%8
            slot = next((j for j,x in enumerate(self.ways[iset]) if x is None),self.lru[iset])
            victim = self.ways[iset][slot]
            if victim and victim.dirty and len(self.wb)==2: install = None
        ready = not (install is not None and req and self.misses[install].line%8==setno) and (hit is not None or merge is not None or (match is None and free is not None))
        if req and not ready and free is None and hit is None and match is None:
            self.full_stalls += 1
        # A read missing from memory is inhibited while a matching victim is queued.
        forward = None
        reads = []
        for i,m in enumerate(self.misses):
            if m is None or m.state!='need': continue
            matches = [entry for entry in self.wb if entry.number==m.line]
            if matches:
                if forward is None: forward=(i,matches[-1])
            elif mem_ready:
                reads.append(i)
        read = min(reads) if reads else None
        drain = bool(self.wb) and mem_ready and read is None
        memory_command = None
        if read is not None: memory_command=(False,self.misses[read].line*4,read)
        elif drain: memory_command=(True,self.wb[0].number*4,0)
        fill_response = None
        if fill is not None:
            m=self.misses[fill]; write,addr,value,ident=m.targets[m.cursor]
            if not write: fill_response=(ident,m.data[addr%4])
        out=(int(ready),self.hit_response,fill_response,memory_command,tuple(self.counts))

        # Commit the independent actions in edge order, using the old decisions.
        returned = self.responses.pop(self.cycle,None)
        if returned:
            index,words=returned; m=self.misses[index]
            assert m is not None and m.state=='wait'
            m.state='filled'; m.data=words; m.cursor=0; m.dirty=False
        if forward:
            index,entry=forward; m=self.misses[index]
            m.state='filled'; m.data=entry.words.copy(); m.cursor=0; m.dirty=False
            self.forwarded+=1
            if not allow: self.forwarded_blocked+=1
        if fill is not None:
            m=self.misses[fill]; write,addr,value,ident=m.targets[m.cursor]
            if write: m.data[addr%4]=value; m.dirty=True
            m.cursor+=1
            if m.cursor==len(m.targets): m.state='install'
        pushed=None
        if install is not None:
            m=self.misses[install]; iset=m.line%8
            victim=self.ways[iset][slot]
            if victim and victim.dirty: pushed=Line(victim.number,victim.words.copy(),True)
            self.ways[iset][slot]=Line(m.line,m.data.copy(),m.dirty)
            self.lru[iset]=1-slot; self.misses[install]=None
        if drain:
            old=self.wb.pop(0)
            self.memory[4*old.number:4*old.number+4]=old.words
            self.busy=4; self.counts[3]+=1
        if pushed: self.wb.append(pushed)
        if read is not None:
            m=self.misses[read]; m.state='wait'
            self.responses[self.cycle+10]=(read,self.memory[4*m.line:4*m.line+4].copy())
            self.busy=1
        self.hit_response=None
        if req and ready:
            write,addr,value,ident=req
            if hit is not None:
                entry=self.ways[setno][hit]; self.lru[setno]=1-hit
                if write: entry.words[addr%4]=value; entry.dirty=True
                else: self.hit_response=(ident,entry.words[addr%4])
                self.counts[0]+=1
            elif merge is not None:
                self.misses[merge].targets.append(req); self.counts[2]+=1
            else:
                self.misses[free]=Miss(line,'need',[req]); self.counts[1]+=1
        if self.busy: self.busy-=1
        self.peak_misses=max(self.peak_misses,sum(m is not None for m in self.misses))
        self.cycle+=1
        return out

def workload():
    # Directed overlap, same-line merging, stores, and LRU conflict pressure.
    ops=[(False,0,0),(False,4,0),(False,8,0),(False,12,0),
         (False,1,0),(True,2,0x12345678),(False,2,0),
         (True,32,0x98765432),(True,64,0xABCDEF01),
         (False,0,0),(False,32,0),(False,64,0)]
    state=98731
    for _ in range(180):
        state=(state*1664525+1013904223)&0xffffffff
        addr=(state>>16)&255; write=bool(state>>31)
        state=(state*1664525+1013904223)&0xffffffff
        ops.append((write,addr,state))
    return [(w,a,d,i%64) for i,(w,a,d) in enumerate(ops)]

def generate():
    c=Cache(); ops=workload(); pending={}; shadow=c.memory.copy(); trace=[]; next_op=0
    for cycle in range(6000):
        req=ops[next_op] if next_op<len(ops) else None
        allow=not (45<=cycle<75 or 115<=cycle<145 or 250<=cycle<275)
        out=c.step(req,allow); ready,hit,fill,command,counts=out
        for result in (hit,fill):
            if result:
                ident,value=result
                assert pending.pop(ident)==value, (cycle,ident,hex(value))
        if req and ready:
            write,addr,value,ident=req
            if write: shadow[addr]=value
            else:
                assert ident not in pending
                pending[ident]=shadow[addr]
            next_op+=1
        trace.append((req,allow,out))
        if next_op==len(ops) and not pending and not any(c.misses) and not c.wb and not c.responses and not c.busy: break
    else: raise AssertionError('reference did not drain')
    assert c.peak_misses==4 and c.full_stalls>0
    assert not pending
    return trace,c

if __name__=='__main__':
    trace,cache=generate()
    print(f'{len(trace)} cycles; {len(workload())} requests; peak MSHRs {cache.peak_misses}; {cache.forwarded} forwards')
