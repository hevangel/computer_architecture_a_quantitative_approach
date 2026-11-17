# Store buffering, fences and message passing

This two-core, two-address teaching machine compares sequentially consistent
(SC) stores with a simplified total-store-order (TSO) model. It accepts at most
one command per cycle. SC stores update shared memory immediately; TSO stores
enter a two-entry FIFO per core. A load forwards the youngest matching local
store or reads shared memory. `DRAIN` commits one oldest store. A `FENCE`
commits one oldest store on each retry and acknowledges only once the buffer is
empty. A full buffer rejects a store. The mode is sampled on reset.

The testbenches enumerate all six program-order-preserving interleavings of the
two-store/two-load store-buffering (SB) test in each mode, with no background
drains, and all 20 interleavings with a fence inserted per core. In the tested
unfenced TSO schedules both loads see zero. In every tested SC or fenced
schedule the `(0,0)` outcome is absent. The tests also check youngest-store
forwarding, full-buffer rejection, FIFO drains and a message-passing sequence
where the flag cannot become visible before the preceding data store.

This is a controlled litmus machine, not an exhaustive model checker for all
TSO schedules: the testbench chooses drains explicitly and the shared command
port serializes operations. It omits caches, coherence transactions, atomic
instructions, background draining and multicopy variations. The full TSO
unfenced outcome set can include other results if drains are interleaved.

Both targeted testbenches passed with Icarus Verilog 14.0 development and GHDL
6.0.0 at 3,960 ns. Verilator 5.055 lint passed with the repository's warning
settings. Run from the repository root:

```sh
python scripts/run_tests.py -v consistency_litmus_tsosb
```

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 5, section 5.6. The design and tests are
independently authored.
