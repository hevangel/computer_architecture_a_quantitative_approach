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
| [`csa_wallace_skip_select`](csa_wallace_skip_select) | carry-skip and carry-select adders and a carry-save multiplier |
| [`ieee754_fpu_fma_bf16`](ieee754_fpu_fma_bf16) | binary32 arithmetic, rounding flags and scaled BF16/FP8 FMA |

SRT division remains planned.
