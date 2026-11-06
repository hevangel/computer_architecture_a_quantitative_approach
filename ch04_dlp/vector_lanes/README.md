# Vector Unit with Parallel Lanes

**Topic:** Chapter 4 (Data-Level Parallelism) and the vector appendix · **Editions:** vector machines appear from
the 1st edition; they become a main chapter (with SIMD and GPUs) in the 5th ·
**Files:** [`sv/vector_unit.sv`](sv/vector_unit.sv), [`vhdl/vector_unit.vhd`](vhdl/vector_unit.vhd)

## Background

A **vector instruction** describes up to `MVL` independent element operations with one instruction fetch and
decode. That cuts instruction bandwidth, removes loop overhead and makes hazards between elements impossible.
Hardware executes the elements through **lanes**: with `L` lanes the unit retires `L` elements per cycle, so

```
cycles per vector instruction = ceil(VL / L)        (+ start-up latency in a real pipelined unit)
```

The book's running example is **DAXPY**, `Y = a*X + Y`. In a scalar ISA it is a loop of load, multiply, add,
store; in a vector ISA it is two arithmetic instructions plus the loads/stores:

```
vmuls  V3, V1, a        ; V3 = a * X
vadd   V2, V3, V2       ; V2 = V3 + Y
```

## Design

* `VREGS` vector registers x `MVL` 32-bit elements (defaults 8 x 16).
* Five operations: `VADD`, `VSUB`, `VMUL` (vector-vector), `VMULS`, `VADDS` (vector-scalar).
* After `start`, the unit is `busy` and each cycle the `L` lanes process elements `pos .. pos+L-1`; any lane
  whose element index is `>= vl` is **masked** and the destination element keeps its old value.
* Element load/store ports (`ld_*`, `rd_*`) are for setting up and inspecting registers while idle.
* Not modelled (see exercises): pipelined start-up latency, **chaining**, strided/gather memory access.

## Verification

Two instances (`L = 4` and `L = 1`) are driven by the same stimulus. For each `VL` the testbench runs DAXPY,
checks every element of `Y` against `a*X + Y` (including that masked elements are untouched), and checks that
each instruction took exactly `ceil(VL/L)` cycles on each instance:

| VL | 4 lanes (2 instr.) | 1 lane (2 instr.) | Speedup |
|---:|-------------------:|------------------:|--------:|
| 16 | 8 | 32 | 4.0x |
| 13 | 8 | 26 | 3.25x |
|  4 | 2 |  8 | 4.0x |
|  1 | 2 |  2 | 1.0x |

Short vectors and ragged lengths (VL = 13 wastes 3 lane-slots) show why vector length matters. The other
opcodes are spot-checked against closed-form results.

## Run it

```bash
make test T=vector_lanes
```

## Exercises

1. Add **chaining**: let `vadd` start consuming `V3` elements as `vmuls` produces them, and measure DAXPY.
2. Add a vector **mask register** and a `VCMP`/masked-add pair to vectorize loops with `if`.
3. Add a banked memory port with unit-stride loads and study bank conflicts for strided access.
4. Compare with a scalar loop on [`rv32i_pipeline5`](../../appC_pipelining/rv32i_pipeline5) for the same DAXPY.
