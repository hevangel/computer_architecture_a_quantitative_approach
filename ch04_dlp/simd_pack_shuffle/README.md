# SIMD packing, extension and permutation

This combinational block implements eight signed 32-to-16-bit saturating
narrows followed by eight signed 16-to-8-bit saturating narrows. It separately
extends eight input bytes to halfwords and eight input halfwords to words,
selecting sign extension or zero extension. Lanes are numbered from the least
significant bits; byte shuffle has eight independent 3-bit selectors, and
halfword shuffle has four independent 2-bit selectors over the lower four input
halfwords. Repeated selectors broadcast a lane.

A separate fixed-wiring 8-by-8 byte transpose maps row-major input element
`[row][column]` to output `[column][row]`. It illustrates a wider permutation
network, not a claim that one 64-bit `PSHUFB` instruction transposes a matrix.
The design models neither instruction execution nor quantization scaling,
rounding, or zero points.

Both testbenches consume the same [Python-generated narrowing vectors](golden.txt),
check sign and zero extension, reverse and broadcast byte/halfword shuffles,
and check all 64 elements of a distinct-valued transpose. The targeted tests
passed with Icarus Verilog 14.0 development and GHDL 6.0.0, finishing at 2 ns;
Verilator 5.055 lint passed with the repository's warning settings. Run from the
repository root:

```sh
python ch04_dlp/simd_pack_shuffle/generate_vectors.py --check
python scripts/run_tests.py -v simd_pack_shuffle
```

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 4, section 4.3. The implementation and
vectors are independently authored.
