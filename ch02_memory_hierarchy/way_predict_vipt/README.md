# VIPT Way Prediction and Critical-Word-First Refill

**Topic:** Way prediction, virtually indexed physically tagged caches, and critical-word-first refill · **Edition:** 6th edition, Chapter 2 §2.3 · **Files:** [SystemVerilog](sv/way_predict_vipt.sv), [VHDL](vhdl/way_predict_vipt.vhd)

## Background

A way predictor reads one likely cache way first; if its physical tag misses, another way can be checked on a later cycle. A virtually indexed physically tagged (VIPT) cache can index in parallel with address translation when the line offset and set-index bits all lie inside the page offset. Critical-word-first refill returns the requested word before the rest of its line. These original models illustrate those ideas from the cited section.

## Design

The blocking, write-through teaching cache has four sets, two ways, four 32-bit words per line, and a one-bit most-recently-used way predictor per set. Its 16-bit virtual and physical addresses are byte addresses supplied together; translation itself is outside the model. A valid request needs matching page offsets and word alignment. `PAGE_BITS` defaults to 12. The implementation reports an unsafe configuration and faults requests when the four line-offset bits plus two set bits exceed the page-offset width. It does not attempt page coloring for configurations with index bits above the page offset.

A predicted-way hit responds one cycle after acceptance and a secondary-way hit takes two. On a miss, an internal 64 KiB backing memory supplies one word per cycle, starting with the requested offset and wrapping through the rest of the line. The requested word responds on the first refill beat; the cache continues to hold `req_ready` low until the fourth beat installs the line. A write updates both cache and backing memory. The way-read counter counts tag/data way probes as an energy proxy, not measured energy or power. With one abstract energy unit per way probe, a predicted hit costs one unit and a secondary hit costs two; refill and backing-memory energy are excluded. The model has a single idealized backing-memory word per cycle and no bank contention or memory latency.

## Verification

Both languages execute the same hand-derived directed sequence. They assert one-cycle predicted hits, two-cycle secondary hits, and a three-cycle first response on cold misses. A miss at word offset three refills in order 3, 0, 1, 2, with the response while refill is still busy. Two virtual pages mapping to the same physical word observe the same write; a mismatched page offset and a configuration with only five page-offset bits fault. The directed trace has four fast hits, two secondary hits, four misses, and sixteen way probes. Finally, 128 deterministic mixed accesses use a separate shadow memory, and all 16,384 backing words are checked. SV and VHDL finish at the same simulated time.

## Run it

```sh
python scripts/run_tests.py -v way_predict_vipt
```

## Exercises

1. Add an external backpressured memory and allow a new request after the critical word returns.
2. Model multiple SRAM banks and quantify conflicts rather than assuming one word every cycle.
3. Implement page coloring or synonym management for an index that extends above the page offset.
