# Packed-Subword SIMD ALU

**Topic:** Chapter 4 (SIMD instruction-set extensions for multimedia: MMX, SSE, AVX and their relatives) · **Editions:** vector, SIMD and GPU architectures share a main chapter from the 5th edition ·
**Files:** [`sv/simd_alu.sv`](sv/simd_alu.sv), [`vhdl/simd_alu.vhd`](vhdl/simd_alu.vhd)

## Background

Multimedia and signal-processing data are narrow: pixels are 8 bits, audio samples 16. Running them on a 64-bit ALU wastes 56 or 48 bits per operation. **SIMD extensions** instead split the wide register into
**lanes** and let one instruction operate on all of them -- "subword parallelism". With 64-bit registers that is 8 byte operations, 4 halfword operations or 2 word operations per instruction, using hardware the
processor already has.

Compared with a vector machine ([`vector_lanes`](../vector_lanes)) SIMD is **fixed-width**: the register size and the lane count are baked into the instruction set (which is why MMX gave way to SSE, AVX and AVX-512 as new
opcodes), there is no vector-length register and no strided or gather memory access. In exchange it is cheap, since it reuses the integer datapath, and needs no new state beyond the registers.

Multimedia SIMD also added operations that scalar ISAs lack:

* **Saturating arithmetic.** Overflow clamps to the largest/smallest value instead of wrapping. A pixel that brightens past 255 should stay white, not turn black.
* **Sum of absolute differences (`PSAD`)** -- the inner loop of video motion estimation.
* **Multiply-add (`PMADD`)** -- adjacent 16-bit products summed into 32 bits, the building block of dot products and convolutions (the same idea as the 8-bit MACs inside a neural-network accelerator).
* Lane-wise compare (producing all-ones/all-zeros masks), min/max, rounding average, per-lane shifts.

## Design

`simd_alu` is combinational: `y = op(a, b, imm)` with `esize` selecting 8 x 8-bit (0), 4 x 16-bit (1) or 2 x 32-bit (2) lanes.

| op | name | per lane | op | name | per lane |
|---:|------|----------|---:|------|----------|
| 0 | `PADD` | `a + b` (wraps) | 10 | `PAVGU` | `(a + b + 1) >> 1`, unsigned |
| 1 | `PSUB` | `a - b` (wraps) | 11 | `PCMPEQ` | all ones if `a == b` |
| 2 | `PADDS` | signed saturating add | 12 | `PCMPGTS` | all ones if `a > b` (signed) |
| 3 | `PSUBS` | signed saturating subtract | 13 | `PMULLO` | low half of `a * b` |
| 4 | `PADDUS` | unsigned saturating add | 14 | `PMADD` | (16-bit only) `y32[i] = a[2i]*b[2i] + a[2i+1]*b[2i+1]` |
| 5 | `PSUBUS` | unsigned saturating subtract | 15 | `PSLL` | shift left (0 if `imm >= width`) |
| 6 / 7 | `PMINU` / `PMAXU` | unsigned min / max | 16 | `PSRL` | logical shift right |
| 8 / 9 | `PMINS` / `PMAXS` | signed min / max | 17 | `PSRA` | arithmetic shift right |
| | | | 18 | `PSAD` | (8-bit only) sum of 8 absolute differences into `y[15:0]` |

**The partitioned adder.** A SIMD add must not let a carry out of one lane leak into the next. Real hardware does not build eight separate adders: it uses the one wide adder and *kills the carry at each lane
boundary*. The standard trick handles the lane MSBs separately (`H` is a mask with a 1 at each lane's top bit):

```
sum  = ((a & ~H) + (b & ~H)) ^ ((a ^ b) & H)         lane MSBs are added without carry-in, the rest cannot carry out of the lane
diff = ((a |  H) - (b & ~H)) ^ ((a ^ ~b) & H)        same for borrows
```

`PADD` and `PSUB` are implemented exactly this way (one 64-bit add/subtract); the other operations are computed lane by lane.

## Verification

* **Directed:** carry isolation (`FF + 01` in a byte stays `00`, with no carry into the next byte; the same bytes added as 16-bit lanes give `0100`), borrow isolation, and the saturation corner cases
  (`F0 + 20 -> FF` saturating vs `10` wrapping, `70 + 20 -> 7F`, `80 + 80 -> 80`, `10 - 20 -> 00`), plus `PSAD` and `PMADD` with hand-computed answers.
* **Exhaustive-style:** every op at every lane width it supports (19 ops, 15 900 operand sets in all, including edge patterns `0`, all-ones, `0x80..`, `0x7F..`, shift counts at and beyond the lane width)
  against a **golden model written differently from the RTL**: each lane is rebuilt bit by bit and processed with plain 64-bit integer arithmetic (floor division for the arithmetic shift, overflow-safe splitting for
  the product's low half), not with masks and shifts.
* **Kernels** against scalar loops, with instruction counts (asserted results; counts printed):

  | Kernel | Result | SIMD instructions | Scalar element-operations |
  |---|---|---:|---:|
  | brightness: saturating `+90` on 64 pixels | identical to a clamping loop; **24 pixels would have wrapped** without saturation | 8 `PADDUS` | 64 |
  | SAD of an 8x8 block (motion estimation) | identical (SAD = 6 173) | 8 `PSAD` (+ adds) | 64 |
  | 16-bit dot product, 32 elements | identical modulo 2^32 | 16 (8 `PMADD` + 8 `PADD`) | 64 (32 multiplies + 32 adds) |
  | saturating audio mix, 32 samples | identical to a clamping loop | 8 `PADDS` | 32 adds + 32 clamps |

Replacing the partitioned adder by a plain 64-bit add (carries leak between lanes), or dropping the unsigned clamp, makes the tests fail.

## Run it

```bash
make test T=simd_alu
```

## Exercises

1. Add `PACKUSWB` / `PUNPCKLBW` (pack and unpack between lane widths), which real SIMD code needs to widen bytes before multiplying.
2. Widen to 128 bits (16 byte lanes) and a second register file; count how the kernels' instruction counts halve.
3. Add a per-lane **mask** and a masked add (predication), the SIMD counterpart of `vector_lanes`'s masking.
4. Implement the kernels as a small program on [`rv32i_pipeline5`](../../appC_pipelining/rv32i_pipeline5) with a SIMD coprocessor and measure the speedup in cycles.
5. Add a fused `PMADD` + accumulate and compare with the 16-instruction dot product above.
