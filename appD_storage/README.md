# Appendix D -- Storage Systems

Dependability (reliability, availability) and the devices that dominate it. Main chapter material through the
4th edition, supplemental afterwards. Mean-time-to-failure and redundancy arithmetic drive the designs.

## Examples

| Example | What it shows |
|---------|---------------|
| [`hamming_secded`](hamming_secded) | (72,64) single-error-correct / double-error-detect code, as on ECC DIMMs |
| [`raid5_parity`](raid5_parity) | XOR parity, failed-disk reconstruction, small-write update |
