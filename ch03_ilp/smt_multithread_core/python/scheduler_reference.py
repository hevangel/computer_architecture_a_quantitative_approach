"""Independent functional/timing reference for a two-thread issue scheduler.

Each thread issues in program order, holds its own register scoreboard and can
have several operations in flight. Two ALU starts and one load start are allowed
per cycle, with at most two total instructions issued. This is an abstract
reference, not the requested RTL or a model of a particular processor.
"""
from dataclasses import dataclass

MASK=(1<<32)-1

@dataclass(frozen=True)
class Instruction:
    op:str
    dst:int
    src:int
    arg:int

@dataclass(frozen=True)
class Result:
    cycles:int
    issued:int
    registers:tuple
    switched:int

class Scheduler:
    def __init__(self, programs, memory, mode, load_latency=7, mul_latency=4, switch_cost=1):
        if len(programs)!=2 or mode not in ('SINGLE','COARSE','FINE','SMT'):
            raise ValueError('two programs and a supported mode are required')
        if min(load_latency,mul_latency)<1 or switch_cost<0: raise ValueError('invalid latency')
        self.programs=programs; self.memory=memory; self.mode=mode
        self.load_latency=load_latency; self.mul_latency=mul_latency; self.switch_cost=switch_cost
        self.regs=[[0]*8 for _ in range(2)]; self.busy=[[False]*8 for _ in range(2)]
        self.pc=[0,0]; self.events=[]; self.cycle=0; self.issued=0; self.active=0; self.rr=0; self.cooldown=0; self.switched=0

    def runnable(self,thread,mem_available=True):
        if self.pc[thread]>=len(self.programs[thread]): return False
        ins=self.programs[thread][self.pc[thread]]
        if ins.op not in ('ADD','MUL','LOAD') or not 0<=ins.dst<8 or not 0<=ins.src<8: raise ValueError('invalid instruction')
        if self.busy[thread][ins.src] or self.busy[thread][ins.dst]: return False
        return mem_available or ins.op!='LOAD'

    def issue(self,thread):
        ins=self.programs[thread][self.pc[thread]]; source=self.regs[thread][ins.src]
        if ins.op=='ADD': value=(source+ins.arg)&MASK; latency=1
        elif ins.op=='MUL': value=(source*ins.arg)&MASK; latency=self.mul_latency
        else:
            address=(source+ins.arg)&MASK
            if address not in self.memory: raise ValueError('unmapped load')
            value=self.memory[address]&MASK; latency=self.load_latency
        self.busy[thread][ins.dst]=True; self.events.append((self.cycle+latency,thread,ins.dst,value)); self.pc[thread]+=1; self.issued+=1
        return ins.op=='LOAD'

    def done_thread(self,thread):
        return self.pc[thread]==len(self.programs[thread]) and not any(self.busy[thread])

    def tick(self):
        remaining=[]
        for due,t,dst,value in self.events:
            if due==self.cycle: self.regs[t][dst]=value; self.busy[t][dst]=False
            else: remaining.append((due,t,dst,value))
        self.events=remaining
        if self.mode=='SINGLE' and self.done_thread(0): self.active=1
        if self.mode=='COARSE' and self.cooldown:
            self.cooldown-=1; self.cycle+=1; return
        if self.mode=='COARSE' and not self.runnable(self.active) and not self.done_thread(1-self.active) and self.runnable(1-self.active):
            self.active=1-self.active; self.switched+=1
            if self.switch_cost:
                self.cooldown=self.switch_cost-1; self.cycle+=1; return
        if self.mode=='FINE': chosen=self.cycle%2
        elif self.mode=='SMT': chosen=self.rr
        else: chosen=self.active
        mem_available=True
        for _ in range(2):
            if self.mode=='SMT':
                first=chosen; second=1-first
                if self.runnable(first,mem_available): t=first
                elif self.runnable(second,mem_available): t=second
                else: break
                chosen=1-t
            elif self.runnable(chosen,mem_available): t=chosen
            else: break
            if self.issue(t): mem_available=False
        if self.mode=='SMT': self.rr=1-self.rr
        self.cycle+=1

    def run(self,limit=10000):
        while not (self.done_thread(0) and self.done_thread(1)):
            if self.cycle>=limit: raise RuntimeError('scheduler did not drain')
            self.tick()
        return Result(self.cycle,self.issued,tuple(tuple(r) for r in self.regs),self.switched)
