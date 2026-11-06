# Chapter 1 -- Fundamentals of Quantitative Design and Analysis

The book's thesis is that architecture is an engineering discipline: measure, model, then decide. Chapter 1
supplies the vocabulary and the equations used everywhere else.

| Idea | Equation |
|------|----------|
| CPU performance | `CPU time = Instruction count x CPI x Clock cycle time` |
| Amdahl's Law | `Speedup = 1 / ((1 - f) + f / s)` |
| Dynamic power | `P = 1/2 x C x V^2 x f` (energy per transition `1/2 C V^2`) |
| Availability | `MTTF / (MTTF + MTTR)` |
| Principle of locality, "make the common case fast", parallelism | design guidelines |

## Examples

| Example | What it shows |
|---------|---------------|
| [`amdahl_speedup`](amdahl_speedup) | Amdahl's Law as a fixed-point hardware unit |

Further performance-equation examples live with the machines that produce the numbers: the CPI breakdown in
[`appC_pipelining/rv32i_pipeline5`](../appC_pipelining/rv32i_pipeline5) is the CPU-time equation in action.
