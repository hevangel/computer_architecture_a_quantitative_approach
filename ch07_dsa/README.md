# Chapter 7 -- Domain-Specific Architectures

With Dennard scaling over and Moore's Law slowing, big efficiency wins now come from architectures tailored to a
domain. Common ingredients: dedicated memories (software-managed, no caches), simpler parallelism that fits the
domain (systolic arrays, SIMD), **reduced precision** (int8 instead of fp32), and a domain-specific language.
New in the 6th edition (TPU, Catapult, Pixel Visual Core); the 7th keeps the chapter and updates the survey.

## Examples

| Example | What it shows |
|---------|---------------|
| [`systolic_array`](systolic_array) | weight-stationary int8 matrix unit with skew/de-skew, as in the TPU |

Planned: convolution line-buffer engine and an activation/quantization stage (see
[`docs/roadmap.md`](../docs/roadmap.md)).
