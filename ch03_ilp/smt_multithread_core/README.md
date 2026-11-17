# Two-Thread Hardware Multithreading

**Topic:** Hardware multithreading and simultaneous issue · **Edition:** 6th edition, Chapter 3 §3.11 · **Files:** [scoreboard reference](python/scheduler_reference.py), [rename reference](python/rename_reference.py), [tests](python/)

## Background

Hardware multithreading can use instructions from another thread when one thread waits for a long-latency operation. A simultaneous multithreading scheduler can draw from both threads in a cycle, subject to shared execution resources. This is an original, simplified teaching example. The example compares four scheduling policies in a deliberately small core.

## Design

The initial reference gives each of two threads an in-order instruction queue, eight private registers and a per-register scoreboard. The model issues at most two instructions per cycle, with up to two ALU starts and one load start. Load and multiply operations complete after configurable latencies; operands are captured at issue. It models single-thread execution, coarse switching on a stall, fixed alternating fine-grained issue, and simultaneous issue. Coarse switching has an explicit one-cycle default cost. Loads read an immutable memory dictionary; there are no branches, register renaming, caches, execution-port occupancy beyond the stated start limits, writeback conflicts or exceptions.

A second reference models independent physical register files, frontend and committed maps, free lists, in-order rename/issue queues and reorder buffers. It dispatches and retires up to two instructions per thread per cycle, issues at most two total, captures physical source tags before allocating destinations, and frees old destinations only at retirement. Execution may complete out of order. This model has no branch recovery and supplies independent timing expectations for the RTL.

## Hardware

The [SystemVerilog](sv/smt_multithread_core.sv) and [VHDL](vhdl/smt_multithread_core.vhd) implementations support the four modes, two independent rename queues and register files, in-order issue and retirement, and shared two-wide issue with one load start per cycle. Their testbenches run the same workload as the rename reference and currently match its cycle counts and final state. They use preloaded, fixed-size instruction memories and a 256-word preloaded read-only data memory; the load address is truncated to eight bits. They do not yet provide a streaming frontend, stores, branches, exceptions or a full ISA. `prog_ready` indicates whether the selected thread can accept a preload write; writes while it is low are ignored. A reset is required before loading a new pair of programs. The opcode input accepts ADD, MUL and LOAD (0, 1 and 2); opcode 3 is reserved and must not be used.

The read port reports a committed register on each rising clock edge. The memory is deliberately simple and wraps load addresses to eight bits. An external fetch or memory system is not modeled.

## Verification

For one synthetic 72-instruction workload, the four modes take 87, 57, 54 and 48 cycles respectively, with identical per-thread final register state. Ten Python tests cover both references. The rename reference checks physical-register conservation and map reconstruction each cycle, tests constrained free lists, independent thread namespaces, and compares 320 randomized instructions with a sequential interpreter. The original tests also check load-use waiting, the one-load-per-cycle limit, operand capture across a younger write, and same-destination ordering. Both HDL testbenches reproduce the four timing results and architectural outputs, check that two simultaneous loads start on separate cycles, exercise WAW and load-use dependencies, verify preload backpressure and thread independence, and compare 128 deterministic arithmetic instructions with a sequential interpreter. A nine-physical-register configuration exercises rename pressure. The ordering is workload-specific, not a guarantee for every program.

## Run it

```sh
python -m unittest discover -s ch03_ilp/smt_multithread_core/python -v
python scripts/run_tests.py -v smt_multithread_core
```

## Exercises

1. Add streaming fetch and a ready/valid interface for external instruction and data memories.
2. Compare its timing, shared-resource arbitration and per-thread architectural state against independently derived traces.
3. Add variable-latency memory, writeback contention and realistic thread-switch costs.
