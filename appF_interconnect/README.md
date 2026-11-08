# Appendix F -- Interconnection Networks

How processors, memories and I/O are wired together: topology (bus, crossbar, ring, mesh, torus, fat tree),
routing, flow control, arbitration and the cost/performance of each. Introduced in the 2nd edition.

## Examples

| Example | What it shows |
|---------|---------------|
| [`rr_crossbar`](rr_crossbar) | N x N crossbar, per-output round-robin arbitration, parallel permutation traffic |
| [`mesh_router`](mesh_router) | wormhole mesh router + 2-D mesh: XY routing, credit flow control, round-robin allocation, credit-loop sizing |

Planned: virtual channels, torus with dateline routing, adaptive routing.
