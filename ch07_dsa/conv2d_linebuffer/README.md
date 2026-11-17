# Streaming 3×3 convolution

This block accepts one signed 8-bit pixel per `in_valid` cycle in row-major
order. Two line buffers and six horizontal delay registers form a 3×3 window;
nine signed 8-bit coefficients produce a signed 32-bit sum. As in many CNN
implementations, the operation is cross-correlation: kernel lane 0 is the
top-left coefficient and the kernel is not reversed. `WIDTH` and `HEIGHT`
specify frame dimensions; after the final pixel, the next accepted pixel begins
a new frame. Idle cycles do not advance the window. The kernel input is sampled
with each accepted pixel and should remain constant when a fixed filter is wanted.

Outputs correspond to complete windows only, with no padding. A 16×16 frame
therefore produces 14×14 = 196 outputs. After the first two columns of an
eligible row, the block emits one output for each accepted pixel. Output is
registered on the accepting clock edge; the interface has no output backpressure.
The 32-bit sum does not include bias, activation, rounding, or requantization.

The independently authored Python model generates a signed test image and all
196 reference results. Both HDL tests compare every output and valid cycle over
two consecutive frames with input stalls, finishing at 5,430 ns. The targeted
Icarus Verilog 14.0 development and GHDL 6.0.0 tests passed, as did Verilator
5.055 lint with the repository's warning settings. Run from the repository root:

```sh
python ch07_dsa/conv2d_linebuffer/generate_vectors.py --check
python scripts/run_tests.py -v conv2d_linebuffer
```

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 7, section 7.3. The code, vectors and
explanations are original.
