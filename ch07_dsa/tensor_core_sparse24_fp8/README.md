# Structured Sparse Tensor Tile

**Reference** — Hennessy, Patterson and Kozyrakis, *Computer Architecture: A Quantitative Approach*, 7th edition (2025), Chapter 7 §§7.4–7.5.

The tile computes D = A × B + C for 4×4 matrices. Sixteen lanes reuse the repository's exact-alignment floating-point core. Each lane performs one binary32-rounded FMA per active cycle, using BF16, FP8 E5M2 or FP8 E4M3FN inputs and signed power-of-two scales. A and the initial C are row-major. B arrives from four combinational weight banks, one per output column. When the weight-read signal is high, each bank supplies one 16-bit word at the shared slot address. The low eight bits carry FP8 values.

Dense mode reads four slots and accumulates in ascending k order. Sparse mode reads two packed weights from each column bank. Each column has two strictly increasing two-bit indices into A. Duplicate or descending indices and an unsupported format complete with an error and no reads. The tile latches A, C, format, metadata and scales on start. The provider supplies the selected weight storage for the duration of the tile.

Both testbenches compare 30 dense and compressed tile pairs against exact rational Python results, including nonzero C, negative operands, subnormal FP8 inputs, scaling, and inexact accumulation. Each tested pair matches bit for bit in all lanes and agrees on accumulated flags. Sparse runs use two compute cycles and eight weight reads. Dense runs use four cycles and 16 reads. Counts exclude metadata reads, launch and any external memory latency. Equality assumes that omitting a zero product preserves the operation's result and flags. NaN, infinity and signed-zero combinations can violate that assumption. This model measures work in simulation. It does not measure physical speed or emulate a vendor FPU.

```sh
python ch07_dsa/tensor_core_sparse24_fp8/python/generate_vectors.py
python scripts/run_tests.py -v tensor_core_sparse24_fp8
```

## Exercises

1. Add a ready/valid weight-bank interface and count compute cycles separately from stalls.
2. Measure how per-column metadata and input-bank conflicts change memory traffic.
