# Virtual-Channel Router: Removing Head-of-Line Blocking

**Topic:** Appendix F (Interconnection Networks: virtual channels, VC and switch allocation, credit flow control per VC) · **Editions:** 2-7 ·
**Files:** [`sv/vc_router.sv`](sv/vc_router.sv), [`sv/vc_net.sv`](sv/vc_net.sv), [`sv/vc_pkg.sv`](sv/vc_pkg.sv) and the same three in [`vhdl/`](vhdl)

## Background

In a **wormhole** network ([`mesh_router`](../mesh_router)) a blocked packet keeps every link it occupies, and any packet queued behind it in the same input FIFO must wait even if its own path is free:
**head-of-line (HOL) blocking**. Dally's fix is the **virtual channel**: split each input buffer into several independent FIFOs (the VCs) that *share* one physical link and are multiplexed onto it flit by flit.
A packet owns one VC per hop from head to tail, so wormhole's "no interleaving inside a channel" still holds, but a blocked packet now blocks only its own VC. The costs: more buffer state per port,
and a more complex router - after routing a head flit must also win an **output VC** (VC allocation), and every cycle the router performs a two-stage **switch allocation** among the VCs.
Because buffering is divided, the *per-VC* depth must still cover the credit round trip to run one stream at full rate.

## Design

`vc_router` has five ports (N, E, S, W, Local), each with `NVC` input VCs of `DEPTH` flits. A flit carries the VC it will occupy at the next router (a 2-bit field the router rewrites hop by hop).
Routing is XY, as before.

* **VC allocation (VA).** A head flit at the front of an idle input VC asks for its output port. Each output port grants one request per cycle (round-robin) and hands the winner the lowest *free* output
  VC; an output VC is busy from the head's grant until the tail has been sent.
* **Switch allocation (SA), separable.** Stage 1: each input port picks, round-robin, one VC that has an output VC, a flit and a **credit** for its downstream VC buffer. Stage 2: each output port picks, round-robin,
  one of the input ports that chose it. The winner moves into the output register with its vc field rewritten.
* **Credits.** One counter per output VC (initially `DEPTH`); a credit pulse carries the VC number. Local ejection needs no credits.
* **Timing.** A head flit written to an input FIFO at the end of cycle *c*: VA in *c+1*, SA in *c+2*, on the link in *c+3* - **three cycles per router**. Body and tail flits only do SA: they stream right behind
  the head, one per cycle. The credit round trip per VC is still four cycles.

`vc_net` builds an `NX x NY` mesh of these routers; each node injects on any VC it has credits for.

## Verification

Hand-derived expectations (cycle numbers are tail-on-ejection minus head-on-injection):

| Test | Derivation | Result |
|------|------------|--------|
| routing table, 14 input/destination combinations, flits on VC 1 | X before Y; leaves on the link 3 cycles after arriving; vc field rewritten to the allocated output VC | pass |
| zero load | `3K + F - 1` for `K = hops + 1` routers and `F` flits: (0,0)->(3,3) 5 flits = **25**, neighbour 1 flit = **6**, self 3 flits = **5**, (3,0)->(0,2) 2 flits = **19**; same on VC 0 and VC 1 | pass |
| credit loop, 40-flit packet over 4 routers | full rate needs per-VC depth >= 4: `3*4 + 39 = ` **51**; with depth *D* < 4 flit *i* leaves at `floor(i/D)*4 + (i mod D)`, so the last flit is late by `floor(39/D)*4 + 39 mod D - 39`: depth 3 -> **64**, depth 2 -> **89** | pass |
| hot spot: 15 nodes send 4 flits to node 0 | 60 flits cannot leave one ejection port in fewer than 60 cycles; the router achieves exactly **60** consecutive cycles (worst packet 65) | pass |

**Head-of-line blocking** (4x1 row): packet C (node 1 -> 3, 60 flits) holds router 1's East output; A (node 0 -> 3, 20 flits) queues behind it; the short packet B (node 0 -> 1, 4 flits) is injected right behind A.
With **one VC** B sits in A's queue and completes at cycle **93** (after C has passed). With **two VCs** B uses the second VC, overtakes A, and completes at cycle **13** (bound `3*2 + 4 - 1` plus sharing the
injection port with A). A itself finishes at 91 / 50 - with two VCs it also shares router 1's East link with C instead of waiting for it.

**Random traffic**, 16 nodes x 12 packets of 1-6 flits on the 4x4 mesh, every configuration with the *same* 8 flits of buffering per port:

| Buffering per port | average latency | all 192 packets delivered by cycle |
|--------------------|----------------:|-----------------------------------:|
| 1 VC x 8 flits | 28.06 | 143 |
| 2 VC x 4 flits | **21.88** | **110** |
| 4 VC x 2 flits | 22.99 | 126 |

Splitting the same storage into two VCs wins; four VCs of two flits each lose again because depth 2 cannot cover the 4-cycle credit loop (see the credit-loop row above): the VC count and the per-VC depth trade off.

Checks on every delivery: right destination, flits in order, no interleaving of packets *inside a virtual channel* (interleaving between VCs is expected), each packet exactly once, full length, no
FIFO overflow, latency >= zero-load bound, no deadlock. Mutation checks that fail the testbench in both languages: ignoring credits, letting VC allocation hand out a busy output VC, not rewriting the vc field;
(SystemVerilog also: never freeing an output VC at the tail). Both languages report identical numbers.

## Run it

```bash
make test T=vc_router
```

## Exercises

1. Make the head spend only two cycles by doing VA and SA **speculatively in the same cycle** (a head bids for the switch while it requests a VC) and recompute the zero-load formula.
2. Replace the separable allocator by a **wavefront** allocator and compare throughput under the random traffic.
3. Add a **torus** (wrap-around links) and use two VCs per direction with **dateline** routing to break the cyclic dependency (the classic use of VCs for deadlock avoidance).
4. Reserve one VC for *replies* and one for *requests* to avoid **protocol deadlock** in a request/reply network, and demonstrate the deadlock without it.
5. Add **adaptive** west-first routing and show that the VCs let it use more of the mesh's path diversity.
