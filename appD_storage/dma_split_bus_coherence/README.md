# DMA, split transactions and I/O coherence

**Topic:** I/O, DMA and cache coherence · **Editions:** 1–7 · **Files:** [SystemVerilog](sv/dma_split_bus_coherence.sv), [VHDL](vhdl/dma_split_bus_coherence.vhd)

## Background

DMA lets a device transfer data without a CPU instruction for each word. When a device writes memory behind a CPU cache, a previously cached value can become stale. Hardware snooping can invalidate that copy. For background see Hennessy and Patterson, *Computer Architecture: A Quantitative Approach*, 1st edition (1990), §§9.5–9.7, and 3rd edition (2002), §7.3. This original model illustrates the mechanisms rather than implementing a commercial bus.

## Design

A submitted descriptor contains a starting word address, a 1–16 word length, direction and a snoop flag. Invalid zero-length or out-of-range descriptors set `desc_error` and do not start; a valid descriptor clears the error. Peripheral data passes through separate four-word input and output FIFOs using ready/valid streams. Memory is 16 32-bit words; CPU accesses have priority whenever the single-outstanding bus port is free. DMA issues each memory request separately and receives a response on the following cycle. For peripheral-to-memory transfers it waits for each input word; for the reverse direction it deposits each word into the output FIFO, which holds data stable until accepted. Completion means the last word has entered the output FIFO; the peripheral may still have words to drain. FIFOs persist across descriptors and reset clears them. Completion asserts a sticky IRQ, cleared by `irq_ack` or a new descriptor. Starts while busy are ignored.

The CPU has one write-through cached word. A DMA write with snooping enabled invalidates a matching cache entry at commit; without snooping it deliberately leaves the stale value. The model does not implement dirty CPU lines, DMA descriptor fetch/chaining, multiple outstanding requests or a real bus protocol. CPU accesses must obey `cpu_ready`, input producers must hold data while waiting for `periph_in_ready`, and output consumers use `periph_out_ready`.

## Verification

Both self-checking testbenches use identical stimuli and finish at 1260 ns. They fill the input FIFO, confirm backpressure, transfer and read back four words, then fill and drain the output FIFO in order. They prime a CPU cache, transfer three peripheral words without snooping and demonstrate a stale read; eviction exposes the new memory contents. A second transfer enables snooping and verifies fresh readback. The reverse transfer checks all three words and holds each output under backpressure. Tests also check interrupt acknowledgement and rejected zero-length, out-of-range and overflow descriptors. Both simulators and Verilator lint passed.

## Run it

```sh
python scripts/run_tests.py -v dma_split_bus_coherence
```

## Exercises

1. Fetch and chain descriptors from memory and report invalid descriptors through an error interrupt.
2. Add dirty write-back CPU lines and snoop writeback before a DMA read.
3. Implement multiple tagged outstanding requests and measure arbitration fairness.
