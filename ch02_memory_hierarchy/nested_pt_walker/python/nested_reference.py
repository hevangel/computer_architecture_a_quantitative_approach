"""Independent two-stage, two-level nested translation model.

The root index is eleven bits and the leaf index nine bits.  A root leaf
therefore describes a 2 MiB page; ordinary leaves describe 4 KiB pages.
Page-table words are addressed in host physical memory. Guest page-table
addresses themselves go through the host walk. This is a pedagogical format,
not the encoding or permission rules of a particular ISA.
"""
from collections import OrderedDict
from dataclasses import dataclass

VALID=1
HUGE=2
PAGE=12
SUPER=21
MASK32=(1<<32)-1

class TranslationFault(Exception):
    pass

def pte(base, *, huge=False):
    bits=SUPER if huge else PAGE
    if base<0 or base>MASK32 or base & ((1<<bits)-1):
        raise ValueError('misaligned or out-of-range page base')
    return base | VALID | (HUGE if huge else 0)

@dataclass(frozen=True)
class Translation:
    physical: int
    page_bits: int
    memory_reads: int
    tlb_hit: bool

class Walker:
    def __init__(self, memory, host_root, *, pwc=True, tlb_entries=8):
        if host_root & 0x1fff or not 0<=host_root<=MASK32:
            raise ValueError('host root must be 8 KiB aligned')
        if tlb_entries<1: raise ValueError('TLB requires at least one entry')
        self.memory=memory
        self.host_root=host_root
        self.use_pwc=pwc
        self.pwc={}
        self.tlb=OrderedDict()
        self.capacity=tlb_entries
        self.reads=0

    def _read(self, address):
        if address & 3 or not 0<=address<=MASK32: raise TranslationFault('invalid PTE address')
        if self.use_pwc and address in self.pwc: return self.pwc[address]
        self.reads+=1
        value=self.memory.get(address,0)
        if self.use_pwc: self.pwc[address]=value
        return value

    @staticmethod
    def _leaf(word, offset_bits, address):
        if not word & VALID: raise TranslationFault('invalid page-table entry')
        base=word & 0xfffff000
        if base & ((1<<offset_bits)-1): raise TranslationFault('misaligned superpage')
        return base | (address & ((1<<offset_bits)-1))

    def _host(self, guest_physical):
        if not 0<=guest_physical<=MASK32: raise TranslationFault('guest physical address out of range')
        root_index=(guest_physical>>SUPER)&0x7ff
        root=self._read(self.host_root+4*root_index)
        if not root & VALID: raise TranslationFault('invalid host root')
        if root & HUGE: return self._leaf(root,SUPER,guest_physical),SUPER
        leaf_addr=(root & 0xfffff000)+4*((guest_physical>>PAGE)&0x1ff)
        leaf=self._read(leaf_addr)
        if leaf & HUGE: raise TranslationFault('huge bit in host leaf')
        return self._leaf(leaf,PAGE,guest_physical),PAGE

    def _guest_pte(self, guest_physical):
        host_physical,_=self._host(guest_physical)
        return self._read(host_physical)

    def translate(self, virtual, asid, guest_root):
        if not (0<=virtual<=MASK32 and 0<=asid<=0xffff): raise ValueError('address or ASID out of range')
        if guest_root & 0x1fff or not 0<=guest_root<=MASK32: raise ValueError('guest root must be 8 KiB aligned')
        before=self.reads
        for key,(physical_base,bits) in list(self.tlb.items()):
            stored_asid,stored_bits,vpn=key
            if stored_asid==asid and stored_bits==bits and virtual>>bits==vpn:
                self.tlb.move_to_end(key)
                return Translation(physical_base | (virtual & ((1<<bits)-1)),bits,0,True)
        root=self._guest_pte(guest_root+4*((virtual>>SUPER)&0x7ff))
        if not root & VALID: raise TranslationFault('invalid guest root')
        if root & HUGE:
            guest_physical=self._leaf(root,SUPER,virtual); guest_bits=SUPER
        else:
            leaf_address=(root & 0xfffff000)+4*((virtual>>PAGE)&0x1ff)
            leaf=self._guest_pte(leaf_address)
            if leaf & HUGE: raise TranslationFault('huge bit in guest leaf')
            guest_physical=self._leaf(leaf,PAGE,virtual); guest_bits=PAGE
        physical,host_bits=self._host(guest_physical)
        effective=min(guest_bits,host_bits)
        key=(asid,effective,virtual>>effective)
        self.tlb[key]=(physical & ~((1<<effective)-1),effective)
        self.tlb.move_to_end(key)
        if len(self.tlb)>self.capacity: self.tlb.popitem(last=False)
        return Translation(physical,effective,self.reads-before,False)

    def invalidate(self, asid=None):
        """Page-table edits need PWC invalidation; optionally drop one ASID's TLB."""
        self.pwc.clear()
        if asid is None: self.tlb.clear()
        else:
            for key in list(self.tlb):
                if key[0]==asid: del self.tlb[key]
