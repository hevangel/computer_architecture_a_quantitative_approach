# Appendix J -- Computer Arithmetic

Integer and floating-point arithmetic implemented in hardware: fast adders, multipliers, dividers, and the IEEE
754 standard. (Appendix lettering follows the 5th edition; earlier editions placed arithmetic in a different
appendix.)

## Examples

| Example | What it shows |
|---------|---------------|
| [`carry_lookahead_adder`](carry_lookahead_adder) | generate/propagate, two-level lookahead |
| [`booth_multiplier`](booth_multiplier) | radix-4 Booth recoding, 8 partial products for 16 bits |
| [`restoring_divider`](restoring_divider) | shift-subtract division, one quotient bit per cycle |

Planned: IEEE 754 single-precision adder and multiplier, SRT division, fused multiply-add.
