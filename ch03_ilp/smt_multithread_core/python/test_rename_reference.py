import unittest
from random import Random
from scheduler_reference import Instruction as I
from rename_reference import RenameScheduler
from test_scheduler_reference import workload

class RenameTests(unittest.TestCase):
    def test_all_modes_match_sequential_architecture(self):
        programs = [workload(0), workload(1)]
        results = [RenameScheduler(programs, {0: 11, 1: 17}, mode).run()
                   for mode in ('SINGLE', 'COARSE', 'FINE', 'SMT')]
        self.assertTrue(all(r.issued == 72 for r in results))
        self.assertTrue(all(r.registers == ((0,11,5,5,5,5,32,12), (0,17,5,5,5,5,32,18)) for r in results))
        self.assertEqual([r.cycles for r in results], [87, 57, 54, 48])
        self.assertGreater(results[1].switched, 0)

    def test_waw_can_complete_out_of_order_but_retires_in_order(self):
        c = RenameScheduler([[I('MUL',1,0,2), I('ADD',1,0,5)], []], {}, 'SMT')
        c.tick(); self.assertEqual(len(c.rob[0]), 2)
        self.assertEqual(c.front[0][1], 9)
        self.assertEqual(c.rob[0][1].old, 8)
        c.tick(); self.assertTrue(c.rob[0][1].done)
        self.assertEqual(c.committed[0][1], 1)
        result = c.run()
        self.assertEqual(result.registers[0][1], 5)
        self.assertEqual(len(c.free[0]), 12)

    def test_random_rename_chains_against_sequential_interpreter(self):
        rng = Random(5192)
        programs = []
        expected = []
        for _ in range(2):
            regs = [0] * 8; prog = []
            for _ in range(160):
                op = rng.choice(('ADD','MUL'))
                src, dst, arg = rng.randrange(8), rng.randrange(8), rng.randrange(1, 8)
                prog.append(I(op, dst, src, arg))
                regs[dst] = ((regs[src] + arg) if op == 'ADD' else (regs[src] * arg)) & 0xffffffff
            programs.append(prog); expected.append(tuple(regs))
        for mode in ('SINGLE','COARSE','FINE','SMT'):
            c = RenameScheduler(programs, {}, mode, nphys=11, rob_size=8)
            self.assertEqual(c.run().registers, tuple(expected))
            self.assertGreaterEqual(max(c.max_live), 3)
            self.assertEqual([len(f) for f in c.free], [3,3])

    def test_thread_namespaces_and_rename_pressure(self):
        programs = [[I('ADD',1,0,5), I('ADD',2,1,1)],
                    [I('ADD',1,0,9), I('ADD',2,1,2)]]
        c = RenameScheduler(programs, {}, 'SMT', nphys=9, rob_size=8)
        c.tick()
        self.assertEqual([c.front[t][1] for t in range(2)], [8, 8])
        self.assertEqual([len(c.rob[t]) for t in range(2)], [1, 1])
        result = c.run()
        self.assertEqual(result.registers[0][1:3], (5,6))
        self.assertEqual(result.registers[1][1:3], (9,11))
        self.assertEqual([len(f) for f in c.free], [1,1])

    def test_memory_resource_and_load_dependencies(self):
        programs = [[I('LOAD',1,0,0), I('ADD',2,1,3)], [I('LOAD',1,0,1)]]
        c = RenameScheduler(programs, {0:5, 1:9}, 'SMT', load_latency=3)
        c.tick(); self.assertEqual(c.issued, 1)
        c.tick(); self.assertEqual(c.issued, 2)
        self.assertEqual(c.run().registers, ((0,5,8,0,0,0,0,0),(0,9,0,0,0,0,0,0)))

if __name__ == '__main__': unittest.main()
