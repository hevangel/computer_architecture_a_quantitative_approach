import unittest
from scheduler_reference import Instruction as I, Scheduler

def workload(thread):
    result=[I('ADD',6,6,1)]
    for k in range(5):
        result.append(I('LOAD',1,0,(k+thread)%2))
        result.extend(I('ADD',2+j,2+j,1) for j in range(4))
        result.append(I('ADD',7,1,1)); result.append(I('MUL',6,6,2))
    return result

class SchedulerTests(unittest.TestCase):
    def test_modes_preserve_thread_state_and_relative_throughput(self):
        programs=[workload(0),workload(1)]; memory={0:11,1:17}
        modes=('SINGLE','COARSE','FINE','SMT')
        results=[Scheduler(programs,memory,mode).run() for mode in modes]
        self.assertEqual([r.cycles for r in results],[87,57,54,48])
        self.assertTrue(all(r.issued==72 for r in results))
        self.assertTrue(all(r.registers==((0,11,5,5,5,5,32,12),(0,17,5,5,5,5,32,18)) for r in results))
        self.assertGreater(results[1].switched,0)

    def test_single_memory_start_per_cycle(self):
        c=Scheduler([[I('LOAD',1,0,0)],[I('LOAD',1,0,1)]],{0:5,1:9},'SMT')
        c.tick(); self.assertEqual(c.issued,1)
        c.tick(); self.assertEqual(c.issued,2)
        self.assertEqual(c.run().registers[1][1],9)

    def test_load_use_waits_for_result(self):
        c=Scheduler([[I('LOAD',1,0,0),I('ADD',2,1,3)],[]],{0:5},'SMT',load_latency=3)
        r=c.run(); self.assertEqual((r.cycles,r.registers[0][2]),(5,8))

    def test_older_reader_captures_before_younger_write(self):
        c=Scheduler([[I('MUL',2,1,3),I('ADD',1,0,9)],[]],{},'SMT')
        c.regs[0][1]=4; r=c.run()
        self.assertEqual((r.registers[0][1],r.registers[0][2]),(9,12))

    def test_same_destination_is_not_written_out_of_order(self):
        c=Scheduler([[I('MUL',1,0,2),I('ADD',1,0,5)],[]],{},'SMT')
        r=c.run(); self.assertEqual(r.registers[0][1],5)

if __name__=='__main__': unittest.main()
