# Torus with Dateline Virtual-Channel Classes

**Topic:** Appendix F (topology: tori; deadlock avoidance with virtual channels) · **Editions:** 2-7 ·
**Files:** [`sv/torus_router.sv`](sv/torus_router.sv), [`sv/torus_net.sv`](sv/torus_net.sv), [`vhdl/torus_router.vhd`](vhdl/torus_router.vhd), [`vhdl/torus_net.vhd`](vhdl/torus_net.vhd)
(the flit format comes from [`vc_router`](../vc_router), pulled in through `deps.txt`)

## Background

A **torus** is a mesh with wrap-around links: every row and every column is a **ring**. The diameter halves (a `k x k` torus has diameter `2 floor(k/2)` instead of `2(k-1)`) and
the average distance drops, at the price of longer wires and a new problem. In a ring, with wormhole switching, packets can wait for each other **in a cycle**: every packet holds the link
it is on and needs the link ahead, which another packet holds. Unlike on a mesh, dimension-order routing alone does not prevent this - the cycle is inside one dimension.

The classic cure (Dally & Seitz) uses [virtual channels](../vc_router): cut each ring at a **dateline** and split the VCs into two **classes**.

* a packet starts every dimension in class 0;
* crossing the dateline link moves it to class 1, where it stays until it leaves that ring;
* turning into the next dimension restarts at class 0.

A packet takes the shorter way round, so it travels at most half a ring and crosses the dateline at most once. Class-0 channels then only wait for class-0 channels further along (up to the
dateline), class-1 channels only for class-1 channels beyond it: the **channel dependency graph has no cycle**, hence no deadlock.

## Design

`torus_router` is the virtual-channel router of [`vc_router`](../vc_router) (VC allocation, separable switch allocation, per-VC credits, 3 cycles per router for a head flit) with two changes:

* **Routing:** per dimension the shorter way round (`d = (dest - here) mod k`; East/South if `d <= k/2`, otherwise West/North, so a tie goes East/South), X before Y.
* **VC allocation:** the output VC is chosen from the class `cout`: `1` if the output link is a wrap-around link (East from `x = NX-1`, West from `x = 0`, South from `y = NY-1`, North from `y = 0`);
  otherwise the packet's current class if it continues in the same ring, `0` if it enters a new dimension. Ejection takes any VC. Classes are the lower and upper half of the VCs
  (`NVC` even); parameter `DATELINE = 0` switches the restriction off, to demonstrate the deadlock.

`torus_net` wires `NX x NY` routers with wrap-around links.

## Verification

**Single routers** (five routers of a 4x4 torus, 22 probes with a single-flit packet each, expected values derived by hand from the rules above): the output port and the output VC.
For example router (0,0): destination (1,0) -> East VC 0, (2,0) -> East (tie), (3,0) -> **West VC 1** (wrap-around link, class 1), (0,3) -> **North VC 1**, (3,3) -> West (X first);
router (3,0): any flit leaving East is class 1, a flit from class 1 that turns South restarts at **VC 0**; router (1,0): class 1 stays class 1 going East, class 0 stays class 0, ejection takes the lowest VC;
router (0,3): South is the wrap-around link of the Y ring -> VC 1.

**Zero load** `3K + F - 1` with `K = ring distance in X + ring distance in Y + 1` routers: (0,0)->(3,0) with 5 flits = **10** (a mesh needs 4 routers: 16), (0,0)->(2,0) = 13,
(0,0)->(3,3) = **13** (mesh: 25), (1,1)->(3,3) = 19, (0,3)->(0,0) over the Y wrap = 10, self = 5.

**Deadlock and its cure** (negative controls included):

| Traffic | 1 VC, no dateline | 2 VCs with dateline |
|---------|-------------------|---------------------|
| ring of 4: every node sends a 20-flit packet two hops East | **0 of 4 delivered** (deadlock) | all 4 by cycle 88 |
| 4x4 torus, every node sends 16 flits to (x+2, y+2) | **0 of 16 delivered** (deadlock) | all 16 by cycle 130 |

**Random traffic** (192 packets of 1-6 flits): 2.01 hops on average on the torus against 2.59 on a mesh; average latency 22.02 cycles with 2 VCs x 4 flits (zero-load average 11.66) and
19.72 with 4 VCs x 2 flits (two VCs per class), all delivered by cycle 132 / 120; every latency is at least its zero-load bound, packets arrive complete, in order, once, with no
interleaving inside a virtual channel and no FIFO overflow.

Mutation checks that fail the testbench in both languages: the dateline not setting class 1, the class not restarting at a turn, the tie going West, the dateline on the wrong link;
(SystemVerilog also: the class not kept inside a ring). Both languages report identical numbers.

## Run it

```bash
make test T=torus_dateline
```

## Exercises

1. Show that **two VCs without classes** do *not* make the ring safe in general: find a traffic pattern with three packets per link that deadlocks `DATELINE = 0, NVC = 2`.
2. Replace the dateline by **bubble flow control**: a packet may enter a ring only if a free buffer remains, so one VC suffices; compare buffer cost and throughput.
3. Make the torus **bidirectional with minimal-path ties broken randomly** (or adaptively) and check which turns / classes keep it deadlock-free.
4. Extend to a **3-D torus** and count the VCs needed with dimension-order routing and datelines.
5. Compare the 4x4 torus with the 4x4 mesh of [`vc_router`](../vc_router) under uniform random, transpose and tornado traffic.
