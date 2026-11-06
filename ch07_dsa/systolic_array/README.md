# Systolic Matrix-Multiply Unit (TPU-style)

**Topic:** Chapter 7 (Domain-Specific Architectures) · **Editions:** 6-7 ·
**Files:** [`sv/systolic_array.sv`](sv/systolic_array.sv), [`vhdl/systolic_array.vhd`](vhdl/systolic_array.vhd)

## Background

After Dennard scaling ended, the book argues, large efficiency gains must come from **domain-specific
architectures**. Neural-network inference is dominated by dense matrix multiplication, so Google's TPU devotes
most of its die to a **systolic array** of multiply-accumulate (MAC) units: data pulses through a regular grid,
each value is fetched from memory once and reused by many MACs, and there is no instruction fetch or cache in
the datapath. An `N x N` array performs `N^2` MACs per cycle.

This module is the **weight-stationary** form used in the TPU: weights are loaded once and stay put while
activations stream through.

```
C[m][n] = sum over k of  A[m][k] * W[k][n]        A: int8 activations   W: int8 weights   C: int32
```

## Design

```
             column n -->
                 W[0][0]  W[0][1]  ...        activations flow RIGHT
  row k   a ->  [ PE ] -> [ PE ] -> ...       partial sums flow DOWN
  (skewed)       |          |
  a ->          [ PE ] -> [ PE ] -> ...
                 v          v
                 C[m][0]    C[m][1]   (de-skewed on the way out)
```

`PE(k,n)` holds `W[k][n]`. Each cycle it multiplies the activation arriving from the left by its weight, adds
the partial sum arriving from above, registers the result downward and forwards the activation to the right.

**Skewing.** Row `A[m][*]` is presented as a whole vector in one cycle, so the module delays row `k` by `k`
cycles on entry (input skew). Then the wavefront for result row `m` reaches `PE(k,n)` in cycle `m + k + n`, just
as the partial sum from `PE(k-1,n)` (computed one cycle earlier) arrives. The result for column `n` is ready
in cycle `m + N + n`; delaying column `n` by `N-1-n` aligns every column:

```
latency = 2N - 1 cycles        throughput = one result row per cycle
```

For `N = 4` that is 7 cycles of latency and 16 MACs per cycle once full. Weights are loaded one row per cycle
through `w_we/w_row/w_data`.

> **Implementation note (SystemVerilog).** Icarus Verilog mis-extends narrow signed *array elements* when
> they are multiplied in a wider context. The RTL therefore copies each operand into a full-width signed
> temporary before the multiply.

## Verification

A 4x4 weight matrix and nine activation rows of random int8 values (with `-128` and `127` planted in the first
rows to test extremes) are streamed in as **five back-to-back rows, an idle gap, then four more rows**.
A concurrent checker compares each output row with a nested-loop golden product **and** requires every row to
emerge exactly `2N - 1 = 7` cycles after it was sent, so skew mistakes show up as latency or data errors. Both
languages finish at 340 ns.

## Run it

```bash
make test T=systolic_array
```

## Exercises

1. Parameterize `N = 8` and plot MACs/cycle against area (the PEs are the area).
2. Switch to an **output-stationary** dataflow, where partial sums stay in the PEs and both operands stream.
3. Add a ReLU/quantize stage at the bottom, as the TPU's activation unit does, to make a complete layer.
4. Tile a larger matrix product through the array and count the cycles lost to load/drain.
