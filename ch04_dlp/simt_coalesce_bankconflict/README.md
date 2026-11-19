# SIMT memory counts, scoreboard and barrier

**Topic:** GPU SIMT memory and synchronization · **Editions:** 5–7 · **Files:** [SystemVerilog](sv/simt_coalesce_bankconflict.sv), [VHDL](vhdl/simt_coalesce_bankconflict.vhd)

## Background

A GPU can combine lane accesses to the same memory line, while simultaneous shared-memory accesses to one bank may require replay. Separate warp scoreboards prevent a warp from reading an unfinished result, and a block barrier waits for all participating warps. See Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), §4.4. This is an original teaching model, not a model of a particular GPU.

## Design

A 32-bit lane mask selects up to 32 byte addresses. The combinational global counter counts distinct aligned 64-byte lines; the shared-memory counter reports the maximum number of active addresses mapping to any of 32 four-byte banks. The shared model serializes even identical addresses and does not implement multicast. Addresses are assumed to represent single aligned four-byte accesses; crossing-line accesses are outside the model. The separate `simt_memory_engine` latches one warp request and emits aligned line addresses and lane masks using ready/valid handshakes, or emits one replay mask per conflict-free shared-bank round. Requests stay stable under backpressure; `accepted_requests` counts handshakes. The `simt_memory_system` wrapper executes those accepted masks against separate 256-word global and shared memories and collects per-lane load results. Addresses index words by bits 9:2 (wrapping every 1,024 bytes); host initialization and readback are available while idle. The caller must supply aligned, in-range addresses and avoid multiple lanes writing the same word in one request. The memory model completes an accepted request on that edge and does not model latency, faults or independent response ordering.

Eight independent 32-register scoreboards track pending destinations. A warp can issue only when its selected source and destination registers are not pending and it is not waiting at the barrier. A valid accepted issue marks the destination; writeback clears it. The barrier collects arrivals from a caller-supplied participant mask, holds arriving warps, and pulses release after all participants arrive. The mask must remain fixed until release and warps must arrive only after their own earlier operations complete. The standalone multi-register scoreboard and configurable barrier illustrate the mechanisms separately. The core has its own per-register scoreboard and a fixed all-warps barrier.

The `simt_coalesced_core` wrapper connects the core's optional asynchronous memory interface to global and shared memory. It supports up to eight warps and 32 lanes, queues up to `QUEUE_DEPTH` requests (default four) while one request is serviced by the memory system, and returns a tagged response for each completed request. The core can issue independent instructions and additional loads with distinct destinations while earlier loads are pending; it stalls on dependencies, serializes stores, and waits for all operations before exit. The wrapper accepts requests concurrently with service but drains them in FIFO order through a single coalescer; it does not return responses out of order. `allow_request` can stall emitted transactions. `run` holds only the core in reset, allowing host initialization; change it only after the queue and memory system are idle. The global reset also resets the memory system and transaction counter. Opcodes `LDS` and `STS` select shared memory, while `BARRIER` waits until every warp has arrived after completing its own outstanding operation. All warps must reach each barrier in the same order; an exited or nonparticipating warp causes deadlock.

## Verification

Both testbenches exercise 8, 16 and 32 active lanes. Contiguous four-byte accesses produce 1, 1 and 2 line transactions respectively (a 32-lane warp occupies 128 bytes); a 64-byte lane stride produces one transaction per active lane. A four-way shared-bank conflict reports four cycles, and a conflict-free case reports one. Tests also check a RAW stall, another warp's independence, writeback and two consecutive four-warp barriers. The engine tests check the two emitted contiguous lines, all 32 separate stride requests, four conflict replay masks, empty requests and stalled output. A data-bearing test checks 32 coalesced global loads, masked global stores and four-round shared stores/loads, including every returned value. End-to-end tests run two warps through coalesced loads and stores with backpressure, check every result and transaction count, then run a divergent branch program through coalesced stores. A third program delays one warp, exchanges values with the other through two-way shared-bank conflicts, and executes two barriers under backpressure. A fourth holds the memory engine stalled while five loads fill the active slot and queue, verifies that a sixth stalls, then checks all results after draining. Bypassing the barrier in a mutation test corrupts the cross-warp results.

## Run it

```sh
python scripts/run_tests.py -v simt_coalesce_bankconflict
```

## Exercises

1. Build a multi-engine memory endpoint that can return tagged responses out of order.
2. Replace the fixed scratch memories with a latency-bearing request/response interface.
3. Add same-address broadcast and support explicitly selected barrier participants.
