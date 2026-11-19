# 4×4 stencil over an 8×8 scratchpad

**Topic:** image stencil accelerators · **Editions:** 6–7 · **Files:** [SystemVerilog](sv/stencil_halo_2d.sv), [VHDL](vhdl/stencil_halo_2d.vhd)

## Background

Image accelerators apply the same neighborhood operation at many positions. A tile needs a one-pixel halo from adjacent tiles or an edge policy at image boundaries. See Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), §7.7, for the Pixel Visual Core context. This is an original functional model rather than that device's implementation.

## Design

Load an 8×8 unsigned-byte image into a 64-entry scratchpad, then start a pass selecting horizontal Sobel, vertical Sobel, an unnormalized 3×3 box sum, or a one-pixel N/S/E/W shift, and clamp or wrap edges. Sixteen combinational lanes produce signed 16-bit values for each 4×4 tile in row-major lane order. Four tile results use ready/valid handshaking, so a stalled output remains stable. Input writes are accepted only while idle. `load_count` counts accepted loads modulo 128 and does not count scratchpad reads; reset clears the counter but does not clear the image.

A 6×6 bank of local row registers holds each 4×4 tile and its one-pixel halo. Each lane selects its N/S/E/W neighbor from adjacent buffered positions; diagonal values use horizontal shifts of the N/S rows. Shift mode exposes these four directions, with `shift_direction` values 0–3 for north, south, east and west.

The tile loader reads one scratchpad byte per cycle. The first tile in each row loads 36 positions; the right-hand tile reuses the two overlapping buffered columns and loads 24. Thus a pass performs 36 + 24 + 36 + 24 = 120 scratchpad reads, versus 144 for reloading all four halos. `scratch_read_count` resets at the start of each pass and counts these reads. `busy` stays high while loading and producing results; `out_valid` rises only when a complete tile is buffered. Output backpressure does not trigger more reads. The external `load_count` still measures host writes, not scratchpad reads; no external image refetch is required after the initial 64 writes. The model has a single read per cycle and parallel arithmetic, but does not model physical memory timing, energy or area. The user must load all image locations before starting.

## Verification

The independent Python generator computes all 64 pixels for both boundary policies and all three filters. Both HDL testbenches preload the image once, check 24 filter and 32 directional-shift tile results against those vectors, hold every filtered tile under two cycles of backpressure, attempt ignored writes during loading and output stalls, exercise an always-ready consumer, and confirm the external load counter stays at 64. They verify cumulative scratchpad counts of 36, 60, 96 and 120 at the four tiles. Both simulations passed at 19,900 ns and Verilator lint passed. A mutation that replaced reused columns with zero failed the first right-hand tile.

## Run it

```sh
python ch07_dsa/stencil_halo_2d/generate_vectors.py --check
python scripts/run_tests.py -v stencil_halo_2d
```

## Exercises

1. Reuse the overlapping rows across tile rows and compare scratchpad reads.
2. Explore a wider scratchpad port and measure throughput under output backpressure.
3. Add separable filters and configurable coefficients.
