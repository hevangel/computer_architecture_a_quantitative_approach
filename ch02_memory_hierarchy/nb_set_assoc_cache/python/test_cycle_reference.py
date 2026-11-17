import unittest
from cycle_reference import Cache, generate, workload

class ReferenceTests(unittest.TestCase):
    def test_direct_hit_and_primary_miss_timing(self):
        c=Cache()
        request=(False,0,0,1)
        self.assertTrue(c.step(request,True)[0])
        outputs=[c.step(None,True) for _ in range(15)]
        self.assertEqual([(i+1,x[2]) for i,x in enumerate(outputs) if x[2]],[(12,(1,0x5A000000))])
        self.assertTrue(c.step((False,0,0,2),True)[0])
        self.assertEqual(c.step(None,True)[1],(2,0x5A000000))

    def test_trace_exercises_pressure_and_forwarding(self):
        trace,c=generate()
        self.assertEqual(c.peak_misses,4)
        self.assertGreater(c.forwarded,0)
        self.assertGreater(c.full_stalls,0)
        self.assertEqual(len(workload()),192)
        self.assertTrue(any(req and not out[0] for req,_,out in trace))
        self.assertTrue(any(not allowed for _,allowed,_ in trace))
        self.assertEqual(c.counts[0]+c.counts[1]+c.counts[2],len(workload()))

if __name__=='__main__': unittest.main()
