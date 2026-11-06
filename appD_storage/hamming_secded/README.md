# SECDED (72,64) Error-Correcting Code

**Topic:** storage and memory reliability (Appendix D, and the DRAM discussion in Chapter 2) ·
**Editions:** 1-7 (ECC on memories is part of the dependability material from the first edition) ·
**Files:** [`sv/hamming_secded.sv`](sv/hamming_secded.sv), [`vhdl/hamming_secded.vhd`](vhdl/hamming_secded.vhd)
(each defines `secded_encoder` and `secded_decoder`)

## Background

Large DRAM arrays suffer soft errors (a cosmic ray flips a bit). Server memories add check bits so errors can be
fixed on the fly. A **Hamming code** places check bits at the power-of-two positions `1, 2, 4, 8, ...`; check bit
`2^k` is the parity of every position whose index has bit *k* set. If one bit is flipped, the recomputed parities
form a **syndrome** whose binary value is exactly the index of the bad bit.

Hamming distance 3 corrects one error but would mistake two errors for a different single error. Adding one
**overall parity** bit raises the distance to 4: **Single-Error Correction, Double-Error Detection (SECDED)**.
For 64 data bits this needs 7 Hamming check bits + 1 overall bit = **72 bits**, the standard ECC DIMM width
(12.5 % overhead).

| Overall parity | Syndrome | Meaning | Action |
|:---:|:---:|---------|--------|
| even | 0 | no error | pass through |
| odd  | 0 | the overall-parity bit itself flipped | correct bit 0 |
| odd  | nonzero (< 72) | single-bit error at index = syndrome | flip that bit, `single_err` |
| even | nonzero | two errors | `double_err` (uncorrectable) |
| odd  | >= 72 | three or more errors | `double_err` |

## Design

Codeword bit 0 is the overall parity; bits 1-71 are Hamming positions with check bits at 1, 2, 4, 8, 16, 32, 64
and the 64 data bits filling the other positions in ascending order. The encoder places the data, computes each
check bit over its covered positions, then the overall parity over bits 1-71. The decoder recomputes the
7-bit syndrome and the overall parity, applies the table above, and extracts the data bits.

## Verification

For 12 data words (all zeros, all ones, and ten pseudo-random) the testbench checks: the clean codeword decodes
without flags; **all 72 single-bit errors** are corrected and flagged `single_err`; and **all 2 556 double-bit errors**
(every pair `i < j`) raise `double_err` and not `single_err`. That is 864 single-error and 30 672 double-error
patterns per language.

## Run it

```bash
make test T=hamming_secded
```

## Exercises

1. Pipeline the decoder and report its depth; ECC adds latency to every DRAM read.
2. Implement **chipkill**-style symbol correction (Reed-Solomon over 4-bit symbols).
3. Add a scrubber that reads, corrects and writes back memory in the background.
