# RV32C subset expansion and fetch

The combinational decoder expands `C.ADDI`, `C.LW`, `C.SW`, `C.BEQZ`, `C.J`,
`C.JAL`, `C.MV` and `C.ADD` into corresponding 32-bit RV32I encodings. Hints
within those encodings expand normally; other compressed encodings are flagged
`illegal`, meaning **unsupported by this subset**, not necessarily illegal in
the complete ISA. Inputs whose bottom two bits are `11` pass through as a
32-bit word without validation; encodings longer than 32 bits are not handled.

`rvc_fetch` accepts a little-endian 32-bit window beginning at the supplied PC
and returns the expansion, its two- or four-byte length and the sequential next
PC. The caller provides the window, including bytes crossing a word boundary.
There is no memory interface, stall handling, exception logic or integrated CPU.
In particular, a consumer must use the original instruction length for a
compressed `C.JAL` return address; the existing `rv32i_pipeline5` assumes
four-byte instructions and cannot be connected unchanged.

An independent field-based Python reference generates expected results for all
49,152 16-bit patterns with compressed-length prefixes, including unsupported
patterns; its instruction-field mappings were checked against LLVM's RISC-V
compressed-instruction definitions and encoding test vectors. Both HDL tests
compare every pattern and check a 32-bit pass-through. They also execute a
mixed-width loop in a small testbench interpreter: its six static instructions
occupy 18 rather than 24 bytes (25% less), and its 13 executed instructions
fetch 36 rather than 52 bytes (about 30.8% less). These are measurements of
that synthetic loop, not a general code-size claim.

Targeted tests passed with Icarus Verilog 14.0 development and GHDL 6.0.0,
finishing at 49,166 ns in both languages; Verilator 5.055 lint passed with the
repository's warning settings. Run from the repository root:

```sh
python appA_isa/rvc_compressed_decoder/generate_vectors.py --check
python scripts/run_tests.py -v rvc_compressed_decoder
```

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 6th edition (2017), Appendix A and Appendix K.2. The implementation
and test vectors are independently authored.
