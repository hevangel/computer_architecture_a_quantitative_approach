# Carry-skip, carry-select and carry-save arithmetic

These unsigned combinational blocks illustrate two 16-bit adders and an 8-by-8
multiplier. `carry_skip16` propagates carries through four-bit groups when all
four operand bits differ. `carry_select16` computes both possible group sums
and selects one when the preceding carry is available. `wallace8` reduces eight
partial-product rows through six 3:2 carry-save compressors and adds the final
two rows. The carry-save network has four sequential compression levels before
the final carry-propagate adder. These structural counts are educational proxies,
not measured gate delay, synthesized area, or a claim of optimal physical layout.

All three have matching SystemVerilog and VHDL interfaces. Adders take `a`, `b`
and `cin` and return `sum` and `cout`; the multiplier takes 8-bit operands and
returns a 16-bit product. The testbenches enumerate all 65,536 operand pairs for
the multiplier, compare addition against the language arithmetic operators for
those pairs and 10,000 deterministic full-width pairs, and check a 16-bit carry
chain. They are designed to run via:

```sh
python scripts/run_tests.py -v csa_wallace_skip_select
```

**Verification status:** the targeted runner passed both testbenches with Icarus
Verilog 14.0 development and GHDL 6.0.0, completing all exhaustive and random
checks at 75,537 ns in each language.

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Appendix J, sections J.8–J.9. The implementations
and tests are independently authored.
