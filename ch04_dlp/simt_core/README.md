# A GPU-Style SIMT Core

**Topic:** Chapter 4 (vector, SIMD and GPU architectures) · **Editions:** GPUs get a dedicated main chapter from the 5th edition (little coverage before) ·
**Files:** [`sv/simt_core.sv`](sv/simt_core.sv), [`vhdl/simt_core.vhd`](vhdl/simt_core.vhd)

## Background

A GPU achieves throughput not with deep out-of-order pipelines but with **many threads** and **cheap, wide execution**. Three ideas carry the design:

1. **SIMT (single instruction, multiple threads).** Threads are grouped into **warps** (32 on NVIDIA GPUs; 8 here). A warp shares one program counter: each
   cycle the core fetches one instruction and executes it for every **active** lane in lock-step. Fetch, decode and control are amortized over the lanes.
2. **Latency hiding by multithreading.** A load takes many cycles. Instead of stalling, the scheduler switches to *another warp*. With enough resident
   warps the execution lanes are busy while memory works -- the GPU's answer to what caches and out-of-order execution do for a CPU.
3. **Branch divergence.** When lanes of a warp disagree on a branch, the hardware runs the two paths one after the other with the lanes of the *other* path
   **masked off**, then **reconverges**. Divergence wastes lane slots:

   ```
   SIMT efficiency = (active lane-slots used) / (issued warp-instructions x lanes per warp)
   ```

## Design

* `NW` warps x `WS` lanes (defaults 4 x 8), per-lane registers `r0..r7` (`r0 = 0`), a single issue slot per cycle, round-robin warp selection.
* **Scheduler.** Each cycle the first *ready* warp after the last one issued is chosen (ready = not finished and not waiting for a load). If none is ready the cycle
  is idle.
* **Loads.** The data is captured when the load issues and written to the registers `LD_LAT - 1` edges later; the warp cannot issue again until then, i.e. its
  next instruction issues `LD_LAT` edges after the load (`LD_LAT = 6`). Other warps keep running.
* **Divergence stack** (the SSY/SYNC scheme used by NVIDIA GPUs of the Tesla/Fermi era):

  | Instruction | Action |
  |---|---|
  | `SSY` | push a token holding the current active mask |
  | `BEQZ ra, T` | lanes with `ra == 0` jump to `T`, the others fall through. All jump / none jump: no divergence. Otherwise **push** `{pc = T, mask = taken}` and continue with the not-taken lanes |
  | `SYNC` | **pop**. A pending path: run it (`pc`, `mask` from the entry). An SSY token: restore its mask and continue after the `SYNC` |
* ISA: `ADD SUB MUL ANDI ADDI TID LD ST BEQZ BRA SSY SYNC EXIT`; word-addressed memory with one port per lane. `TID` yields the global thread id (`warp*WS + lane`).
* **Simplified on purpose:** a warp blocks on any load (real GPUs track per-register scoreboards so independent instructions continue); no caches, coalescing
  or bank conflicts; one issue slot; one SIMT stack scheme (recent GPUs have independent thread scheduling).

## Verification

**Divergent kernel (PROG 0):** `y[tid] = x[tid] even ? 3*x[tid] : x[tid] + 100` with `x[tid] = tid`.

```
 0 TID r1          5 ADDI r4,r2,100   (odd path)    10 ST [r1+64],r4
 1 LD  r2,[r1]     6 BRA 9                           11 EXIT
 2 ANDI r3,r2,1    7 ADDI r5,r0,3    (even path)
 3 SSY             8 MUL r4,r2,r5
 4 BEQZ r3, 7      9 SYNC            (reconvergence)
```

The active-lane count of each dynamic instruction of one warp, which gives the hand-derived totals:

| Instruction | `TID LD ANDI SSY BEQZ` | `ADDI BRA SYNC` (odd lanes) | `SYNC` pops -> `ADDI MUL SYNC` (even lanes) | `SYNC` pops SSY -> `ST EXIT` |
|---|:---:|:---:|:---:|:---:|
| active lanes | 8 each | 4 each | 4 each | 8 each |
| lane-slots | 40 | 12 | 12 | 16 |

So 13 warp-instructions and **80 lane-ops** per warp: **SIMT efficiency 80 / (13 x 8) = 0.77**. The testbench checks every `y[tid]`, the
instruction and lane-op counts, and the cycle counts. The cycle counts come from an **independent Python model** of the round-robin policy:

| Warps | Cycles | Idle cycles | Warp-instr | Cycles / warp-instr |
|------:|-------:|------------:|-----------:|--------------------:|
| 1 | 18 | 5 | 13 | 1.38 |
| 4 | **54** | **2** | 52 | 1.04 |

Running the four warps one after another would take 4 x 18 = 72 cycles; interleaving them takes 54 because the load latency of one warp is covered by the
others. **Uniform kernel (PROG 1)** has a `BEQZ` that every lane takes and one that no lane takes, so there is no divergence: SIMT efficiency is exactly **1.0**,
7 warp-instructions and 56 lane-ops per warp, no idle cycles. Breaking the reconvergence (a `SYNC` that does not restore the mask) corrupts every lane's result,
and shortening the load latency changes the cycle and idle counts; both are caught.

## Run it

```bash
make test T=simt_core
```

## Exercises

1. Sweep `NW` from 1 to 8 on the divergent kernel and plot idle cycles: how many warps does it take to hide a 6-cycle load, and how does that change with `LD_LAT`?
2. Add a per-register scoreboard so a warp can keep issuing independent instructions after a load (and measure the benefit).
3. Add **nested** divergence (an `if` inside an `if`) and check the stack depth needed.
4. Add address **coalescing**: count how many distinct memory lines a warp's load touches and charge latency accordingly.
5. Compare the lane-op throughput with [`vector_lanes`](../vector_lanes) for the same DAXPY kernel.
