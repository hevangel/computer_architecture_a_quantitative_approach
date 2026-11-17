"""Functional reference for physical-register renaming and precise rollback.

Completion order is supplied by the caller, allowing tests to explore legal
out-of-order schedules. Values reside in the PRF; ROB entries hold tags only.
This is a reference model, not a timed hardware engine.
"""
from collections import deque
from dataclasses import dataclass

MASK=(1<<32)-1

@dataclass
class Entry:
    seq: int
    op: str
    sources: tuple[int,...]
    architectural: int|None = None
    new: int|None = None
    old: int|None = None
    predicted: bool = False
    done: bool = False

class RenameEngine:
    def __init__(self, initial, physical=24, rob_size=8):
        self.narch=len(initial)
        if self.narch<1 or physical<=self.narch or rob_size<1: raise ValueError('invalid resources')
        self.physical=physical; self.rob_size=rob_size
        self.prf=[0]*physical; self.ready=[False]*physical
        for i,value in enumerate(initial): self.prf[i]=value&MASK; self.ready[i]=True
        self.arch_map=list(range(self.narch)); self.front_map=self.arch_map.copy()
        self.free=deque(range(self.narch,physical)); self.rob=deque(); self.next_seq=0; self.squashes=0
        self.check()

    def issue(self,op,dst=None,src1=None,src2=None,predicted=False):
        if op not in ('ADD','SUB','MUL','BNEZ'): raise ValueError('unsupported operation')
        if len(self.rob)==self.rob_size: raise BufferError('ROB full')
        if op!='BNEZ' and not self.free: raise BufferError('physical registers exhausted')
        indices=(src1,) if op=='BNEZ' else (src1,src2)
        if any(not isinstance(i,int) or i<0 or i>=self.narch for i in indices): raise ValueError('invalid source')
        if op!='BNEZ' and (not isinstance(dst,int) or dst<0 or dst>=self.narch): raise ValueError('invalid destination')
        sources=tuple(self.front_map[i] for i in indices)
        new=old=None
        if op!='BNEZ':
            old=self.front_map[dst]; new=self.free.popleft(); self.ready[new]=False; self.front_map[dst]=new
        entry=Entry(self.next_seq,op,sources,dst if op!='BNEZ' else None,new,old,predicted)
        self.next_seq+=1; self.rob.append(entry); self.check(); return entry.seq

    def can_complete(self,seq):
        entry=next((e for e in self.rob if e.seq==seq),None)
        return bool(entry and not entry.done and all(self.ready[p] for p in entry.sources))

    def complete(self,seq):
        entry=next((e for e in self.rob if e.seq==seq),None)
        if not entry or not self.can_complete(seq): raise ValueError('entry missing or operands not ready')
        vals=[self.prf[p] for p in entry.sources]
        if entry.op=='BNEZ':
            actual=vals[0]!=0; entry.done=True
            if actual!=entry.predicted:
                survivors=deque(e for e in self.rob if e.seq<=seq)
                removed=[e for e in self.rob if e.seq>seq]
                self.rob=survivors; self.squashes+=len(removed)
                # Rebuild against the *current* architectural map: older writes
                # may have committed after the branch was issued.
                self.front_map=self.arch_map.copy()
                for old_entry in self.rob:
                    if old_entry.new is not None: self.front_map[old_entry.architectural]=old_entry.new
                used=set(self.arch_map)|{e.new for e in self.rob if e.new is not None}
                remaining=[p for p in self.free if p not in used]
                remaining.extend(p for p in range(self.physical) if p not in used and p not in remaining)
                self.free=deque(remaining)
        else:
            a,b=vals
            result={'ADD':lambda:a+b,'SUB':lambda:a-b,'MUL':lambda:a*b}[entry.op]()&MASK
            self.prf[entry.new]=result; self.ready[entry.new]=True; entry.done=True
        self.check()

    def commit(self):
        if not self.rob or not self.rob[0].done: return False
        entry=self.rob.popleft()
        if entry.new is not None:
            assert self.arch_map[entry.architectural]==entry.old
            self.arch_map[entry.architectural]=entry.new
            self.free.append(entry.old)
        self.check(); return True

    def architectural(self): return [self.prf[p] for p in self.arch_map]

    def check(self):
        assert len(self.arch_map)==len(self.front_map)==self.narch
        used=set(self.arch_map)|{e.new for e in self.rob if e.new is not None}
        free=set(self.free)
        assert len(free)==len(self.free) and not free&used
        assert used|free==set(range(self.physical))
        expected=self.arch_map.copy()
        for entry in self.rob:
            if entry.new is not None: expected[entry.architectural]=entry.new
        assert self.front_map==expected
        assert len(set(self.arch_map))==self.narch
        assert all(0<=p<self.physical for p in self.front_map)
