# Chapter 7 -- Domain-Specific Architectures

With Dennard scaling over and Moore's Law slowing, big efficiency wins now come from architectures tailored to a
domain. Common ingredients: dedicated memories (software-managed, no caches), simpler parallelism that fits the
domain (systolic arrays, SIMD), **reduced precision** (int8 instead of fp32), and a domain-specific language.
New in the 6th edition (TPU, Catapult, Pixel Visual Core); the 7th keeps the chapter and updates the survey.

## Examples

| Example | What it shows |
|---------|---------------|
| [`systolic_array`](systolic_array) | weight-stationary int8 matrix unit with skew/de-skew, as in the TPU |
| [`tensor_core_sparse24_fp8`](tensor_core_sparse24_fp8) | dense and compressed tensor tiles with scaled BF16/FP8 and FP32 accumulation |
| [`conv2d_linebuffer`](conv2d_linebuffer) | streaming signed 3×3 convolution with two line buffers |
| [`stencil_halo_2d`](stencil_halo_2d) | buffered Sobel and box stencils with directional halo shifts |
| [`systolic_os_act_quant`](systolic_os_act_quant) | output-stationary matrix multiply with bias, activation and int8 narrowing |

Further work is listed in
[`docs/roadmap.md`](../docs/roadmap.md).
