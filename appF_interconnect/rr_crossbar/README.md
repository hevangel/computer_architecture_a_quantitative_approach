# Crossbar Switch with Round-Robin Arbitration

**Topic:** Appendix F (Interconnection Networks) · **Editions:** interconnection networks from the 2nd edition ·
**Files:** [`sv/rr_crossbar.sv`](sv/rr_crossbar.sv), [`vhdl/rr_crossbar.vhd`](vhdl/rr_crossbar.vhd)

## Background

A shared bus serializes all traffic. A **crossbar** connects every input to every output through a grid of
switches, so any set of requests aimed at *different* outputs proceeds in parallel; the price is `O(N^2)` switch
area. When several inputs want the same output, an **arbiter** must choose. Good arbiters are **fair**
(no starvation) and cheap. **Round-robin** arbitration gives the highest priority to the requester just after the
previous winner, so every persistent requester is served within `N` grants.

Contention causes **head-of-line blocking**: an input whose request loses cannot present the next flit behind
it until the head is accepted. Larger networks (meshes, tori, fat trees, Chapter 6/Appendix F) are built from
many small crossbar switches like this one.

## Design

`N` inputs, each presenting `req`, `dst` and `data`. For every output `j`:

1. The candidate set is the inputs with `req && dst == j`.
2. A pointer `ptr[j]` remembers the last winner; the search starts at `ptr[j] + 1` and wraps.
3. The first candidate found wins: `out_valid[j]`, `out_src[j]`, `out_data[j]` are driven and the winner's
   `in_gnt` bit is set. On the clock edge `ptr[j]` moves to the winner.

The datapath is combinational (the crossbar proper); only the pointers are registered. Pointers reset so the first
winner is input 0.

## Verification

Four scenarios, all checked cycle by cycle:

1. **Hot spot** -- all four inputs target output 2: winners must rotate exactly `0,1,2,3,0,1,2,3`, with the right grant
   vector and data.
2. **Idle input skipped** -- input 1 idle, the rest target output 0: rotation is `0,2,3,0,2,3`.
3. **Permutation traffic** `i -> i+1`: all four requests granted *every* cycle and routed to the correct output
   -- the parallelism a crossbar buys.
4. **3 000 random cycles** -- an output is valid iff someone requested it; the winner must have requested that output
   and received a grant; and the number of grants equals the number of busy outputs.

## Run it

```bash
make test T=rr_crossbar
```

## Exercises

1. Add per-input FIFOs and **virtual output queues** to remove head-of-line blocking; measure throughput.
2. Replace round-robin with a matrix arbiter or a priority scheme with aging.
3. Chain four of these into a 2x2 mesh with dimension-order routing.
