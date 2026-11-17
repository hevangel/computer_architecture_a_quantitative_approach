import unittest
from nested_reference import Walker, TranslationFault, pte, VALID, HUGE

HOST_ROOT=0x2000
HOST_LEAF=0x4000
GUEST_ROOT=0x10000
GUEST_LEAF=0x12000
VIRTUAL=0x00412034

def fixture():
    mem={HOST_ROOT:pte(HOST_LEAF)}
    # Map the guest's page tables and data through the host's ordinary leaves.
    for page in (0x10,0x12,0x18,0x1a,0x20,0x21):
        mem[HOST_LEAF+page*4]=pte(page<<12)
    ri=(VIRTUAL>>21)&0x7ff; li=(VIRTUAL>>12)&0x1ff
    mem[GUEST_ROOT+ri*4]=pte(GUEST_LEAF)
    mem[GUEST_LEAF+li*4]=pte(0x20000)
    mem[GUEST_LEAF+(li+1)*4]=pte(0x21000)
    return mem

class NestedTranslationTests(unittest.TestCase):
    def test_nested_walk_amplification_and_tlb(self):
        c=Walker(fixture(),HOST_ROOT,pwc=False)
        result=c.translate(VIRTUAL,7,GUEST_ROOT)
        self.assertEqual((result.physical,result.page_bits,result.memory_reads,result.tlb_hit),(0x20034,12,8,False))
        result=c.translate(VIRTUAL+12,7,GUEST_ROOT)
        self.assertEqual((result.physical,result.memory_reads,result.tlb_hit),(0x20040,0,True))

    def test_page_walk_cache_reuses_host_and_guest_entries(self):
        c=Walker(fixture(),HOST_ROOT,pwc=True)
        first=c.translate(VIRTUAL,7,GUEST_ROOT)
        second=c.translate(VIRTUAL+0x1000,7,GUEST_ROOT)
        self.assertEqual((first.memory_reads,second.memory_reads),(6,2))
        self.assertEqual(second.physical,0x21034)

    def test_guest_and_host_superpage_expand_tlb_reach(self):
        mem=fixture(); ri=(VIRTUAL>>21)&0x7ff
        mem[GUEST_ROOT+ri*4]=pte(0x200000,huge=True)
        mem[HOST_ROOT+4]=pte(0x400000,huge=True)
        c=Walker(mem,HOST_ROOT,pwc=False)
        first=c.translate(VIRTUAL,1,GUEST_ROOT)
        second=c.translate(VIRTUAL+0x2000,1,GUEST_ROOT)
        self.assertEqual((first.physical,first.page_bits,first.memory_reads),(0x412034,21,4))
        self.assertEqual((second.physical,second.tlb_hit,second.memory_reads),(0x414034,True,0))

    def test_superpage_and_small_page_tlb_keys_do_not_collide(self):
        mem=fixture(); ri=(VIRTUAL>>21)&0x7ff
        mem[GUEST_ROOT+ri*4]=pte(0x200000,huge=True)
        mem[HOST_ROOT+4]=pte(0x400000,huge=True)
        mem[GUEST_ROOT]=pte(GUEST_LEAF); mem[GUEST_LEAF+2*4]=pte(0x20000)
        c=Walker(mem,HOST_ROOT,pwc=False)
        self.assertEqual(c.translate(VIRTUAL,1,GUEST_ROOT).page_bits,21)
        self.assertEqual(c.translate(0x2034,1,GUEST_ROOT).page_bits,12)
        self.assertTrue(c.translate(VIRTUAL+4,1,GUEST_ROOT).tlb_hit)
        self.assertTrue(c.translate(0x2038,1,GUEST_ROOT).tlb_hit)

    def test_host_small_page_limits_effective_tlb_reach(self):
        mem=fixture(); ri=(VIRTUAL>>21)&0x7ff
        mem[GUEST_ROOT+ri*4]=pte(0x200000,huge=True)
        host_leaf2=0x6000; mem[HOST_ROOT+4]=pte(host_leaf2)
        host_index=((0x200000+(VIRTUAL & 0x1fffff))>>12)&0x1ff
        mem[host_leaf2+host_index*4]=pte(0x500000)
        c=Walker(mem,HOST_ROOT,pwc=False)
        result=c.translate(VIRTUAL,1,GUEST_ROOT)
        self.assertEqual((result.physical,result.page_bits,result.memory_reads),(0x500034,12,5))
        with self.assertRaises(TranslationFault): c.translate(VIRTUAL+0x1000,1,GUEST_ROOT)

    def test_asids_remain_distinct_without_flush(self):
        mem=fixture(); ri=(VIRTUAL>>21)&0x7ff; li=(VIRTUAL>>12)&0x1ff
        mem[0x18000+ri*4]=pte(0x1a000); mem[0x1a000+li*4]=pte(0x21000)
        c=Walker(mem,HOST_ROOT,pwc=False)
        self.assertEqual(c.translate(VIRTUAL,1,GUEST_ROOT).physical,0x20034)
        self.assertEqual(c.translate(VIRTUAL,2,0x18000).physical,0x21034)
        self.assertTrue(c.translate(VIRTUAL,1,GUEST_ROOT).tlb_hit)
        self.assertTrue(c.translate(VIRTUAL,2,0x18000).tlb_hit)

    def test_tlb_capacity_replaces_least_recently_used(self):
        mem=fixture(); li=(VIRTUAL>>12)&0x1ff
        mem[GUEST_LEAF+(li+2)*4]=pte(0x22000); mem[HOST_LEAF+0x22*4]=pte(0x22000)
        c=Walker(mem,HOST_ROOT,pwc=False,tlb_entries=2)
        c.translate(VIRTUAL,1,GUEST_ROOT); c.translate(VIRTUAL+0x1000,1,GUEST_ROOT)
        self.assertTrue(c.translate(VIRTUAL,1,GUEST_ROOT).tlb_hit)
        c.translate(VIRTUAL+0x2000,1,GUEST_ROOT)
        self.assertTrue(c.translate(VIRTUAL,1,GUEST_ROOT).tlb_hit)
        self.assertFalse(c.translate(VIRTUAL+0x1000,1,GUEST_ROOT).tlb_hit)

    def test_fault_and_explicit_invalidation(self):
        mem=fixture(); c=Walker(mem,HOST_ROOT,pwc=True)
        self.assertEqual(c.translate(VIRTUAL,1,GUEST_ROOT).physical,0x20034)
        li=(VIRTUAL>>12)&0x1ff
        mem[GUEST_LEAF+li*4]=pte(0x21000)
        self.assertEqual(c.translate(VIRTUAL,1,GUEST_ROOT).physical,0x20034)
        c.invalidate(1)
        self.assertEqual(c.translate(VIRTUAL,1,GUEST_ROOT).physical,0x21034)
        c.invalidate(); mem[GUEST_LEAF+li*4]=0
        with self.assertRaises(TranslationFault): c.translate(VIRTUAL,1,GUEST_ROOT)
        with self.assertRaises(ValueError): pte(0x201000,huge=True)

if __name__=='__main__': unittest.main()
