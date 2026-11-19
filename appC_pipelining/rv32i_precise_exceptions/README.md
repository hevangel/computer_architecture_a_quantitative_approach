# Precise Exceptions in an RV32I Pipeline

**References** — Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 6th edition (2017), Appendix C §C.4, and 1st edition (1990), Chapter 6 §6.5.

This variant retains the five-stage pipeline, forwarding, load-use interlock and execute-stage branch resolution. Each pipeline entry carries its PC and any fault cause. Fetch faults and illegal instructions are tagged before execution. ECALL travels with its instruction to retirement. Data access and alignment faults are resolved in MEM. WB chooses the oldest exception because instructions arrive there in program order. A trapping instruction and every younger instruction lose their write enables. Stores update memory only on their architectural commit edge. The load probe address and commit-store address are distinct, and a simultaneous load from the committed store address uses forwarded data.

A trap saves the PC and cause into MEPC and MCAUSE and redirects to byte address 128. A limited CSRRW implementation reads and writes those two CSRs. CSR operations serialize until retirement. MRET redirects to MEPC and squashes its younger instructions. An IRQ is latched, stops fetch outside the handler, and waits for in-flight instructions to drain. The next unissued PC becomes its saved return address. The model assumes a synchronous external IRQ pulse and a fixed vector. It does not implement full privilege state, nested trap recovery, interrupt masks or a complete CSR file. The fetch port reports instruction access fault for both the supplied fault signal and an unaligned fetch PC.

Both testbenches inject simultaneous older store-access and younger ECALL faults, then show that the earlier store committed while the faulting store did not. They also run isolated illegal-instruction, fetch-fault, IRQ and ECALL cases. The handler reads both saved CSRs, writes a resume address, and returns through MRET. The tests check that wrong-path state stays unchanged and that the resumed program halts normally.

```sh
python scripts/run_tests.py -v rv32i_precise_exceptions
```

## Exercises

1. Add a distinct instruction-address-misaligned cause and check taken branches whose target violates the alignment rule.
2. Add interrupt masking and test a pending interrupt across a synchronous handler and return.
