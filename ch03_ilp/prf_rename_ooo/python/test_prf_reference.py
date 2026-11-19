import unittest
from prf_reference import RenameEngine, MASK

class RenameReferenceTests(unittest.TestCase):
    def test_long_waw_war_chain_against_sequential_state(self):
        initial=[3,5,7,11,13,17,19,23]; expected=initial.copy(); ops=[]; state=1949
        for _ in range(120):
            state=(state*1664525+1013904223)&MASK
            pick=((state>>16)&0x7fff)%6; op='MUL' if pick==0 else ('ADD' if pick&1 else 'SUB'); dst=2+(((state>>2)&7)%6); a=(state>>8)&7; b=(state>>12)&7
            left,right=expected[a],expected[b]
            expected[dst]={'ADD':lambda:left+right,'SUB':lambda:left-right,'MUL':lambda:left*right}[op]()&MASK
            ops.append((op,dst,a,b))
        c=RenameEngine(initial,physical=20,rob_size=8); next_op=0; steps=0; reordered=False
        while next_op<len(ops) or c.rob:
            for _ in range(3):
                if next_op<len(ops):
                    try: c.issue(*ops[next_op]); next_op+=1
                    except BufferError: break
            ready=[e for e in c.rob if c.can_complete(e.seq)]
            if ready:
                chosen=ready[-1]
                if chosen.seq!=c.rob[0].seq: reordered=True
                c.complete(chosen.seq)
            c.commit(); steps+=1
            self.assertLess(steps,2000)
        self.assertTrue(reordered)
        self.assertEqual(expected,[0x00000003,0x00000005,0xfcbe7adc,0x7934b0a5,0x5819034d,0x084b09f0,0x58190350,0xf7b4f615])
        self.assertEqual(c.architectural(),expected)
        self.assertEqual(len(c.free)+len(set(c.arch_map)),c.physical)
        self.assertEqual(c.front_map,c.arch_map)

    def test_branch_rebuild_uses_newly_committed_older_map(self):
        c=RenameEngine([2,1,3,4],physical=10,rob_size=8)
        older=c.issue('MUL',0,0,2); branch=c.issue('BNEZ',src1=1)
        c.issue('ADD',0,0,1); c.issue('SUB',2,2,1)
        c.complete(older); self.assertTrue(c.commit()); self.assertEqual(c.architectural()[0],6)
        c.complete(branch)
        self.assertEqual(c.squashes,2); self.assertEqual(c.front_map,c.arch_map)
        self.assertTrue(c.commit()); self.assertEqual(c.architectural(),[6,1,3,4])
        self.assertEqual(len(c.free),6)

    def test_unfinished_older_writer_survives_branch_squash(self):
        c=RenameEngine([2,1,3,4],physical=9)
        older=c.issue('MUL',0,0,2); branch=c.issue('BNEZ',src1=1)
        c.issue('ADD',0,0,1); c.complete(branch)
        self.assertNotEqual(c.front_map[0],c.arch_map[0]); self.assertFalse(c.can_complete(999))
        c.complete(older); self.assertTrue(c.commit()); self.assertTrue(c.commit())
        self.assertEqual(c.architectural(),[6,1,3,4]); self.assertEqual(len(c.free),5)

    def test_resource_backpressure_and_reuse(self):
        c=RenameEngine([1,2,3,4],physical=6,rob_size=8)
        a=c.issue('ADD',0,0,1); b=c.issue('ADD',1,1,2)
        with self.assertRaises(BufferError): c.issue('ADD',2,2,3)
        c.complete(b); self.assertFalse(c.commit()); c.complete(a); self.assertTrue(c.commit())
        c.issue('ADD',2,2,3); c.check()

    def test_correct_prediction_keeps_younger_work(self):
        c=RenameEngine([0,4],physical=5)
        branch=c.issue('BNEZ',src1=0,predicted=False); younger=c.issue('ADD',1,1,1)
        c.complete(younger); c.complete(branch); self.assertEqual(c.squashes,0)
        self.assertTrue(c.commit()); self.assertTrue(c.commit()); self.assertEqual(c.architectural(),[0,8])

if __name__=='__main__': unittest.main()
