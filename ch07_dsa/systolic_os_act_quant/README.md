# Output-stationary matrix multiply and quantization

This 4×4 signed-int8 array computes `C = A × B`. On `start` while idle it
latches both row-major matrices, sixteen signed 32-bit biases, activation mode
and shift. It skews A rows into the left edge and B columns into the top edge;
each processing element forwards operands to its neighbors and keeps its own
signed 32-bit partial sum. Ten wavefront cycles after acceptance, `done` pulses
and the sixteen accumulators and quantized bytes are available. New starts while
busy are ignored; outputs remain available until the next accepted start.

The post-processor adds bias in 33 bits, optionally clamps negative values to
zero (ReLU), optionally also clamps above six (ReLU6), arithmetic-shifts right,
then clamps to signed int8. Modes 0, 1 and 2 select none, ReLU and ReLU6; the
unused mode 3 behaves like ReLU. The right shift rounds negative values toward
negative infinity. ReLU6's threshold is the integer value 6 before shifting.
This is a simple fixed-point teaching rule, not a complete quantization scheme:
it has no scale multiplier, zero point, saturation flag or rounding mode choice.

The [Python reference](generate_vectors.py) generates three signed matrix cases,
covering all activation modes, positive and negative values, saturation and
extreme 32-bit biases. Both testbenches check all sixteen accumulators and output
bytes, completion latency and latched-input behavior; they finish at 340 ns.
Targeted tests passed with Icarus Verilog 14.0 development and GHDL 6.0.0;
Verilator 5.055 lint passed with the repository's warning settings. From the
repository root:

```sh
python ch07_dsa/systolic_os_act_quant/generate_vectors.py --check
python scripts/run_tests.py -v systolic_os_act_quant
```

For background see Hennessy and Patterson, *Computer Architecture: A Quantitative
Approach*, 7th edition (2025), Chapter 7, sections 7.3–7.4. The implementation,
vectors and explanations are original.
