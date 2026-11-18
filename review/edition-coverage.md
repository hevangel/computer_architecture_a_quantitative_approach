# Edition Coverage Review & Agent Implementation Guide — *Computer Architecture: A Quantitative Approach*

> **Implementation progress:** This review is a baseline snapshot. Subsequent work added
> APPA-2 includes the four-class textbook addition sequence as well as synthetic expression and sort traffic; APPD-3 includes queueing examples and RAID MTTDL checks. CH06-1 includes financed cost, 4M operational carbon and queued replicas, and CH01-2 includes the quantitative suite and a bracketed cost crossover (the 7th-edition extraction omits the power-supply calculation), and CH04-4 covers bounded rectangular affine nests and published roofline examples. Consult the
> [roadmap](../docs/roadmap.md) and the linked model guides for current scope and
> assumptions. CH02-5 has a tested DRAM-cache model with an illustrative predictor;
> its MAP-I-specific implementation remains unverified. CH01-1, CH02-1, CH02-3 (finite 8-bit address space), CH02-4 (safe VIPT indexing and idealized backing memory), CH02-6, CH02-7 (serialized nested walk, four-entry TLB),
> CH03-1, CH03-2 (non-speculative tagged-history model), CH03-3 (RV32I subset), CH03-4 (suffix replay and broadcast-time branch recovery), CH03-5 (external-issue PRF engine), CH03-6 (preloaded two-thread scheduling core), CH03-7 (abstract cache timing model), CH04-1, CH04-2 (core-integrated global coalescing, shared replay, all-warps barrier and per-register scoreboard; queued single-engine memory wrapper), CH04-3 (64-element commands), CH05-1, CH05-2 (serialized reservation monitor and snooping lock model), CH05-3 (serialized directory and replacement model), CH07-1, CH07-2, CH07-4 (single-port buffered halo model), APPA-1, APPD-1, APPD-2, APPE-1 and APPJ-1 have passed targeted RTL testbenches in both
> languages; CH02-2 now has a two-way implementation and directed, shadow-memory, and independent per-cycle model checks. APPJ-3 now has paired HDL testbenches and an exact Python floating-point reference. The remaining RTL work and uncovered portions are incomplete.

The [acceptance plan](edition-acceptance.md) tracks checkpoint evidence and outstanding verification across all 47 numbered items.

## 1. Executive Summary

The companion repository ([`learning/computer_architecture_a_quantitative_approach`](../README.md)) currently provides **33 original hardware examples** (66 self-checking testbenches across SystemVerilog and VHDL) organized into 12 topic directories (`ch01_fundamentals`–`ch07_dsa`, `appC_pipelining`, `appD_storage`, `appF_interconnect`, `appH_vliw`, and `appJ_arithmetic`), accompanied by [`README.md`](../README.md), [`docs/editions.md`](../docs/editions.md), [`docs/roadmap.md`](../docs/roadmap.md), and [`data/index.json`](../data/index.json).

Its strongest coverage is core processor microarchitecture and hardware building blocks:
- **Pipelining (`appC_pipelining`)**: 5-stage RISC-V RV32I (`rv32i_pipeline5`) and DLX/MIPS64 (`mips_pipeline5`) pipelines with forwarding and hazard detection.
- **Memory hierarchy (`ch02_memory_hierarchy`)**: set-associative write-back LRU cache (`set_assoc_cache`), TLB and hardware page-table walker (`tlb_walker`), victim cache (`victim_cache`), stride prefetcher (`stride_prefetcher`), non-blocking write-through cache with MSHRs and coalescing write buffer (`nonblocking_cache`), non-blocking write-back cache with write-back buffer (`writeback_nbcache`), and banked FR-FCFS DRAM controller (`dram_controller`).
- **Instruction-level parallelism (`ch03_ilp`, `appH_vliw`)**: 1-bit/2-bit/gshare branch predictors (`branch_predictor`), CDC 6600 scoreboard (`scoreboard`), Tomasulo with ROB (`tomasulo_rob`), speculative Tomasulo (`tomasulo_spec`), speculative Tomasulo with load/store queue (`tomasulo_lsq`), and a 4-slot statically scheduled VLIW core (`vliw4`).
- **Data- and thread-level parallelism (`ch04_dlp`, `ch05_tlp`)**: vector lanes (`vector_lanes`), vector chaining (`vector_chaining`), packed-subword SIMD ALU (`simd_alu`), GPU-style SIMT core (`simt_core`), MESI snooping coherence (`mesi_snoopy`), directory MSI coherence (`directory_msi`), and snooping-bus TAS/TTAS/ticket spinlocks (`spinlock_atomic`).
- **DSAs, storage, interconnects, and arithmetic (`ch07_dsa`, `appD_storage`, `appF_interconnect`, `appJ_arithmetic`)**: TPU v1-style int8 weight-stationary systolic array (`systolic_array`), SECDED `(72,64)` ECC (`hamming_secded`), RAID-5 parity (`raid5_parity`), round-robin crossbar (`rr_crossbar`), wormhole XY mesh router (`mesh_router`), virtual-channel router (`vc_router`), dateline torus (`torus_dateline`), carry-lookahead adder (`carry_lookahead_adder`), radix-4 Booth multiplier (`booth_multiplier`), and restoring divider (`restoring_divider`).

However, comparing the companion repository and its [`docs/roadmap.md`](../docs/roadmap.md) against all seven textbook editions (1990–2025) reveals substantial gaps in **both whole textbook units and intra-chapter depth**:

1. **Whole chapters and appendices with zero runnable models or directories**:
   - **Chapter 6 (Warehouse-Scale Computers / Request-Level Parallelism, 5th–7th Ed)**: [`ch06_wsc/README.md`](../ch06_wsc/README.md) is guide-only; no RTL or analytical/queueing/cost/cloud models exist yet.
   - **1st Edition Chapter 5 (Basic Processor Implementation Techniques)**: hardwired vs. microprogrammed control, microcode ROMs/sequencers, and unpipelined multi-cycle datapaths (partially echoed only as a planned "unpipelined multicycle baseline" under App A/C in the roadmap).
   - **3rd–4th Edition Chapter 3 / 5th–7th Edition §§3.10–3.12 (Limits on ILP & Hardware Multithreading)**: ILP limit studies and fine-grained, coarse-grained, and simultaneous multithreading (SMT).
   - **Appendix A (Instruction Set Principles, 5th–7th Ed; 1st Ed Ch 3–4; 2nd–3rd Ed Ch 2; 4th Ed App B)**: ISA taxonomy (stack, accumulator, register-memory, load-store), addressing modes, instruction encoding, compiler effects, and dynamic instruction-usage/time-distribution measurements.
   - **Appendix E (Embedded Systems & DSPs, 5th–7th Ed; 3rd Ed inline "Another View" sections; 4th Ed App D)**: DSP Q-format fixed-point/saturating MACs, circular/modulo and bit-reversed addressing, zero-overhead loops, real-time deadlines, EEMBC/Embench metrics, and embedded SoCs. Not on the roadmap.
   - **Appendix G (Vector Processors in More Depth, 3rd & 5th–7th Ed; 1st Ed Ch 7; 4th Ed App F)**: vector memory bank conflicts, strided and gather-scatter addressing, strip-mining, $R_\infty / N_{1/2} / N_v$ asymptotic models, and Cray X1 multi-streaming.
   - **Appendix I (Large-Scale Multiprocessors and Scientific Applications, 5th–7th Ed; 3rd Ed App I; 4th Ed App H)**: non-atomic transient coherence protocol states, scalable synchronization (combining trees, MCS locks, sense-reversing barriers), scientific workload communication-to-computation scaling, and Blue Gene/L networks.
   - **Appendix K (Survey of Instruction Set Architectures, 5th–7th Ed; 1st Ed App B–E; 3rd Ed App C–F; 4th Ed App J)**: desktop/server RISCs, compressed 16/32-bit embedded RISCs (`RV32IC`/`RV64GC`, `Thumb-2`, `MIPS16`/`microMIPS`), and x86/VAX/IBM 360 CISC comparisons.
   - **Appendix L (Advanced Concepts on Address Translation, 6th–7th Ed)**: superpages, coalesced TLBs, MMU/page-walk caches, virtualized/nested translation, and TLB shootdowns.
2. **Major 7th-Edition (2025) architectural topics not yet represented in examples or [`docs/editions.md`](../docs/editions.md)**:
   - Chiplets and monolithic-vs.-chiplet die-yield economics (§1.6), operational vs. embodied carbon emissions (§1.5), Alloy Cache L4 DRAM caching and NUCA (§2.3), cache timing side channels (`Prime+Probe`) and QoS partitioning (§2.4), TAGE branch prediction (§3.3) and Spectre/Meltdown (§3.13), IBM Power10 and Intel Xeon Platinum multicores (§5.8), Meta WSC servers/Yosemite/Lightning, Google Jupiter + Optical Circuit Switches (OCS), AWS Nitro + Graviton3 chiplets (Ch 6), and the completely updated Chapter 7 DSA lineup (TPU v4/v4 lite with 4D Tensor DMA, NVIDIA Volta/Ampere/Hopper/Blackwell Tensor Cores with 2:4 structured sparsity and Transformer Engine, Graphcore Bow IPU, Samsung NPUv1/v2, MLPerf, and the 4M sustainability framework).
3. **Edition-ISA coverage gaps**: Only `appC_pipelining` implements both DLX/MIPS64 (`mips_pipeline5`) and RISC-V (`rv32i_pipeline5`). All other ISA-dependent examples lack DLX (1st–2nd Ed), MIPS64 (3rd–5th Ed), or RV64G/RV64V (6th–7th Ed) variants, and [`docs/editions.md`](../docs/editions.md) omits multiple chapters and appendices from its crosswalk.

This review audits topic coverage and specifies buildable work items; it does not recommend reproducing textbook prose, figures, or exercise solutions. Any new examples or guides must be original and cite the exact edition and section/page.

---

## 2. Agent Implementation Protocol & Repository Contract

Any AI agent adding missing examples or models to [`learning/computer_architecture_a_quantitative_approach`](../README.md) must obey these mechanical rules enforced by [`CLAUDE.md`](../CLAUDE.md), [`scripts/run_tests.py`](../scripts/run_tests.py), and [`scripts/render-index.mjs`](../scripts/render-index.mjs):

### 2.1 Discovery, Layout & Non-RTL Models
- **HDL test-runner discovery rule**: [`scripts/run_tests.py`](../scripts/run_tests.py) recursively discovers **every directory** (outside `.git`, `build`, `scripts`, `docs`, `.github`) that contains an `sv/` or `vhdl/` subdirectory.
- **Required layout for every HDL example (`<group>/<example_name>/`)**:
  - `README.md` — sections: title + `**Topic:** ... **Editions:** ... **Files:** ...`, `## Background`, `## Design`, `## Verification`, `## Run it`, `## Exercises`.
  - `deps.txt` *(optional)* — one repo-relative example path per line (`#` comments allowed), e.g., `appF_interconnect/vc_router`. Pulls that dependency's RTL sources (without its `tb_*`) in before the current module's RTL.
  - `sv/*.sv` — RTL modules plus **exactly one** testbench file named `tb_<name>.sv` whose top-level module is `tb_<name>`. Files ending in `*_pkg.sv` sort first before other RTL.
  - `vhdl/*.vhd` — RTL entities plus **exactly one** testbench file named `tb_<name>.vhd` whose top-level entity is `tb_<name>`. Files are imported via `ghdl -i` and elaborated in dependency order via `ghdl -m` (`*_pkg.vhd` still sorts first).
- **Non-RTL analytical / Python models**:
  - Do **not** create `sv/` or `vhdl/` directories for pure mathematical/queueing/cost/TCO/Roofline scripts (`ch06_wsc`, Ch 1 quantitative suite, App D queueing models), because `run_tests.py` fails any `sv/`/`vhdl/` directory lacking a valid `tb_*` file.
  - Place Python scripts and `unittest`/`pytest` self-checks under `<group>/python/` (stdlib-only Python 3) and add a `test-py` target to [`Makefile`](../Makefile).
- **New top-level group directories**:
  - Add `appA_isa/`, `appE_embedded/` (and optionally `appG_vector/`, `appI_multiprocessors/`, `appK_isa_survey/`, `appL_translation/`—or map G/I/L examples into `ch04_dlp/`, `ch05_tlp/`, and `ch02_memory_hierarchy/` if keeping the 7-chapter + appendix layout compact). Any new top-level group must have its own `<group>/README.md` and a matching entry in [`data/index.json`](../data/index.json).

### 2.2 Simulator Commands, Cross-Language Parity & Toolchain Pitfalls
- **Commands**:
  - SV: `iverilog -g2012 -Wall -Wno-timescale -s tb_<name> -o build/<path>/sv/sim.vvp <sources>` then `vvp -n build/<path>/sv/sim.vvp`
  - VHDL: `ghdl -i --std=08 --workdir=build/<path>/vhdl <sources>`, `ghdl -m --std=08 --workdir=build/<path>/vhdl tb_<name>`, `ghdl -r --std=08 --workdir=build/<path>/vhdl tb_<name> --assert-level=error`
  - Runner: `python3 scripts/run_tests.py -v <example_name>` and `python3 scripts/run_tests.py --lint <example_name>` (or `make test T=<example_name>` / `make lint T=<example_name>`).
- **Pass protocol & parity**:
  - Both SV and VHDL simulators must exit `0`, print `TEST PASSED`, and never print `TEST FAILED`.
  - SV ends with `$finish`; VHDL imports `use std.env.all;` and ends with `finish;`.
  - **Same design & same stimulus**: Both languages must implement identical microarchitecture, port semantics, and test cases. For pseudorandom traffic, use the exact 32-bit LCG `x = (x * 1664525 + 1013904223) mod 2^32`, drawing random numbers into local variables before passing arguments so evaluation order never diverges. Deterministic testbenches should complete at the exact same simulated time in SV and VHDL.
  - **Independent golden reference**: Never copy RTL output into expectations; derive expected values by hand, independent Python scripts, or separate behavioral checks.
- **Must-avoid toolchain pitfalls** (full list in [`CLAUDE.md`](../CLAUDE.md)):
  - *Icarus Verilog (`-g2012`)*: no `break`/`continue` (use `done` flags in `while` loops); no `#delay` inside functions (use `task` with `output`); copy narrow signed unpacked-array elements into full-width `logic signed` temps before multiplying; do not use array literals (`'{...}`) in assignments; assign function results to variables before part-selecting; use fixed-width `logic` vectors instead of `int` arrays in `always_comb` array indexing; use `if`/`case` rather than ternaries when assigning enum variables.
  - *GHDL (`--std=08`)*: VHDL is case-insensitive (never mix `n`/`N` or `s`/`S` for loop vars and generics); **never call an `impure function` from `process(all)`** (pass all read signals as pure-function parameters); repeat `library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;` before every entity in multi-entity `.vhd` files; never name identifiers ending in `_` or using reserved words (`sll`, `srl`, `rol`, `and`, `xor`); guard `process(all)` array indexing at time 0 with `is_x(...)`; use hex bit-string literals (`x"..."`) for 32-bit unsigned/signed constants `>= 2^31`; keep 64-bit integer helper types within `range -(2**56) to 2**56`; explicitly `resize(...)` products/quotients.

### 2.3 Definition-of-Done Checklist (Per New Example)
1. Implement `sv/<name>.sv` + `sv/tb_<name>.sv` and `vhdl/<name>.vhd` + `vhdl/tb_<name>.vhd` (plus `deps.txt` if reusing existing RTL).
2. Verify `python3 scripts/run_tests.py -v <example_name>` passes both `sv` and `vhdl` (and check `python3 scripts/run_tests.py --lint <example_name>`).
3. Author `<group>/<example_name>/README.md` documenting background, module interface/design, exact quantitative verification table, run command, and exercises.
4. Add a row to `<group>/README.md` and the root [`README.md`](../README.md) "What is in the box" table.
5. Update [`docs/editions.md`](../docs/editions.md) topic table and [`docs/roadmap.md`](../docs/roadmap.md) (move item to Done, increment example/test counts).
6. Update expected pass count (`2*N/2*N passed`) in [`CLAUDE.md`](../CLAUDE.md) and [`README.md`](../README.md).
7. Add the example and its source files to [`data/index.json`](../data/index.json).
8. Regenerate `index.html` with `node scripts/render-index.mjs` and verify with `node scripts/render-index.mjs --check`.

---

## 3. Local Textbook Markdown Corpus Audit & Exact Line/Byte-Offset Index

All seven source Markdown files live under [`learning/textbooks/ComputerArchitecture/`](../../textbooks/ComputerArchitecture). Several files have labeling, completeness, or extraction anomalies documented below, followed by exact line/byte coordinates so an agent can use `read_file` directly without scanning whole multi-megabyte files.

### 3.1 Corpus Defects & Caveats
| Local Markdown file | Actual edition & contents present | Missing / defective material in local file |
|---|---|---|
| [`CA_1st_Ed_1990.md`](../../textbooks/ComputerArchitecture/CA_1st_Ed_1990.md) | Complete **1st Edition (1990)**: Chapters 1–10 and Appendices A–E (OCR extracted from `CA_1st_ed_1990_ENGLISH_lccn_1558800698.pdf`, 794 logical book/appendix pages). | Heavy OCR noise on equations, tables, and headings; no structural Markdown chapter headings. |
| [`CA_2nd_Ed_1996.md`](../../textbooks/ComputerArchitecture/CA_2nd_Ed_1996.md) | **Mislabeled file.** Despite its title and cover image (`1558603298`), the body (`chapter_1.pdf`–`chapter_8.pdf`, `appendix-A.pdf`, `appendix-C.pdf`–`appendix-I.pdf`) is actually the **3rd Edition (2002)** text (MIPS64, Intel Pentium 4, IA-64/Itanium, 2000–2001 data). | **True 1996 2nd Edition (DLX) text is missing** from the local Markdown corpus; `appendix-B.pdf` (Exercise Solutions) is also omitted. |
| [`CA_3rd_Ed_2002.md`](../../textbooks/ComputerArchitecture/CA_3rd_Ed_2002.md) | **3rd Edition (2002)** pre-publication/2001 draft (`chap03.2001.pdf`, inline author revision notes) covering Chapters 1–8 and Appendices C–I. | **Appendix A (Pipelining)** and Appendix B (Solutions) are missing from this file (use `CA_2nd_Ed_1996.md` `## appendix-A.pdf` for 3rd-Ed Appendix A). |
| [`CA_4th_Ed_2006.md`](../../textbooks/ComputerArchitecture/CA_4th_Ed_2006.md) | **4th Edition (2006/©2007)** print volume only: Chapters 1–6 and Print Appendices A–C. | **Companion CD Appendices D–L** (Embedded, Interconnects, Vectors, VLIW/EPIC, Large-Scale Multiprocessors, Arithmetic, ISA Survey, Historical Perspectives, Solutions) are listed in the TOC/"About the CD" but absent from the file. |
| [`CA_5th_Ed_2011.md`](../../textbooks/ComputerArchitecture/CA_5th_Ed_2011.md) | **5th Edition (2011/©2012)** Chapters 1–6 and Appendices A–K (both print and online appendices). | **Online Appendix L** (Historical Perspectives and References) is absent; only the TOC entry appears. |
| [`CA_6th_Ed_2017.md`](../../textbooks/ComputerArchitecture/CA_6th_Ed_2017.md) | **6th Edition (2017/©2019)** Chapters 1–7, Print Appendices A–C, and Online Appendices D–K and M. | **Appendix L** (*Advanced Concepts on Address Translation*, Abhishek Bhattacharjee) is only a 1-line external URL placeholder. |
| [`CA_7th_Ed_2025.md`](../../textbooks/ComputerArchitecture/CA_7th_Ed_2025.md) | **7th Edition (2025)** extracted from HTML: Chapters 1–7, Appendices B–K and M, References, and Index. | 1. **Appendix A (Instruction Set Principles)** is missing; the block labeled `Appendix A — Instruction Set Principles (RISC-V)` is actually **Appendix C (Pipelining)**. 2. **Appendix B (Memory Hierarchy Review)** is mislabeled in-line as `Appendix B — Pipelining: Extended`. 3. The **Index** (end of `L7955`) is mislabeled in-line as `Appendix K — RISC-V Case Studies` (while the real Appendix K precedes it). 4. **Appendix L** is again only a 1-line external URL placeholder. 5. Chapters 3–4, part of Chapter 7, and Appendices B, C, F, G, H, I, K, M sit on six multi-hundred-KB single lines (`L1716`, `L2515`, `L3435`, `L4401`, `L6340`, `L7955`) containing residual JS bundle tokens (`',115))])}const F1=i(z,[[`); pass `ByteOffset` to `read_file` when reading those lines. |

### 3.2 Exact Chapter & Appendix Lookup Coordinates (`read_file` Ranges)
| Textbook unit | `CA_1st_Ed_1990.md` | `CA_2nd_Ed_1996.md` *(3rd Ed body)* | `CA_4th_Ed_2006.md` *(Print only)* | `CA_5th_Ed_2011.md` | `CA_6th_Ed_2017.md` | `CA_7th_Ed_2025.md` *(line / ByteOffset)* |
|---|---|---|---|---|---|---|
| Ch 1 (Fundamentals) | `L789–L1740` (Ch 2 cost/perf: `L1741–L3588`) | `L9–L2446` | `L527–L2360` | `L521–L2458` | `L595–L3068` | `L7–L925` |
| Ch 2 (Memory Hierarchy) | `L14419–L17670` (Ch 8) | `L9533–L13066` (Ch 5) | `L7015–L8642` (Ch 5) | `L2459–L4100` | `L3069–L5270` | `L926–L1716` (Bytes `0–15700`) |
| Ch 3 (ILP & Limits) | `L8801–L12520` (Ch 6) | `L4465–L7626` | `L2361–L4976` (Ch 2–3) | `L4101–L6700` | `L5271–L7976` | `L1716` (Bytes `15701–227200`) |
| Ch 4 (DLP: Vector/SIMD/GPU) | `L12521–L14422` (Ch 7 Vectors) | `L26597–L27818` (App G Vectors) | *CD App F (absent)* | `L6701–L8754` | `L7977–L10148` | `L1716` (Bytes `227201–288299`) + `L1717–L2208` |
| Ch 5 (TLP / Multiprocessors) | `L20101–L20880` (Ch 10) | `L13067–L16398` (Ch 6) | `L4977–L7014` (Ch 4) | `L8755–L10636` | `L10149–L12438` | `L2209–L2976` (incl. `L2515`) |
| Ch 6 (WSC & RLP) | — | `L19747–L22014` (Ch 8 §8.10) | `L8643–L10762` (§6.7 cluster) | `L10637–L12192` | `L12439–L14530` | `L2977–L3996` (incl. `L3435`) |
| Ch 7 (DSAs) | — | — | — | — | `L14531–L16500` | `L3997–L4401` (Bytes `0–60198`) |
| App A (ISA Principles) | `L3589–L7100` (Ch 3–4) | `L2447–L4464` (Ch 2) | `L12535–L13636` (App B) | `L12193–L13658` | `L16501–L18180` | *Missing (use 6th Ed)* |
| App B (Mem Hierarchy Review) | `L14419–L15800` (Ch 8.1–8.6) | `L9533–L11000` (Ch 5.1–5.3) | `L13637–L15272` (App C) | `L13659–L15374` | `L18181–L20088` | `L4401` (Bytes `208040–249340`) + `L4402–L4799` *(mislabeled)* |
| App C (Pipelining) | `L7101–L10600` (Ch 5–6.6) | `L22015–L24084` (App A) | `L10763–L12534` (App A) | `L15375–L17664` | `L20089–L21998` | `L4401` (Bytes `60199–208039`) *(mislabeled App A)* |
| App D (Storage & I/O) | `L17671–L20100` (Ch 9) | `L16399–L19746` (Ch 7) | `L8643–L10762` (Ch 6) | `L17665–L19760` | `L21999–L24282` | `L4800–L5744` |
| App E (Embedded & DSP) | — | Inline "Another View" sections | *CD App D (absent)* | `L19761–L20296` | `L24283–L24862` | `L5745–L6049` |
| App F (Interconnects) | `L18400–L19000` (§9.5) | `L19747–L22014` (Ch 8) | *CD App E (absent)* | `L20297–L22584` | `L24863–L27154` | `L6050–L6340` (Bytes `0–167672`) |
| App G (Vectors in Depth) | `L12521–L14422` (Ch 7) | `L26597–L27818` | *CD App F (absent)* | `L22585–L23582` | `L27155–L28206` | `L6340` (Bytes `167673–211482`) |
| App H (VLIW & EPIC) | `L11200–L12000` (§6.8) | `L7627–L9532` (Ch 4) | *CD App G (absent)* | `L23583–L24498` | `L28207–L29122` | `L6340` (Bytes `211483–291757`) |
| App I (Large-Scale MP) | `L20101–L20880` (Ch 10) | `L29495–L29744` | *CD App H (absent)* | `L24499–L25349` | `L29123–L30240` | `L6340` (Bytes `291758–304213`) + `L6341–L6710` |
| App J (Computer Arithmetic) | `L20881–L23108` (App A) | `L27819–L29494` (App H) | *CD App I (absent)* | `L25350–L26993` | `L30241–L32166` | `L6711–L7389` |
| App K (Survey of ISAs) | `L23109–L25050` (App B–E) | `L24085–L26596` (App C–F) | *CD App J (absent)* | `L26994–L29905` | `L32167–L34458` | `L7390–L7955` (Bytes `0–1594`) |
| App L (Address Translation) | — | — | — | — | `L34459–L34478` *(URL stub)* | `L7955` (Bytes `1595–1707`) *(URL stub)* |
| App M (History) / Index | End of chapters | End of chapters | *CD App K (absent)* | *App L absent* | `L34479–L36910` | `L7955` (App M: `1708–247042`; Index: `247043–387884`) |

---

## 4. Edition-by-Edition Structure and Coverage Crosswalk

| Textbook subject | 1st Ed (1990) | 2nd Ed (1996)* | 3rd Ed (2002) | 4th Ed (2006) | 5th Ed (2011) | 6th–7th Ed (2017 / 2025) | Companion directory & status |
|---|---|---|---|---|---|---|---|
| Fundamentals, Cost, Power, Dependability, Benchmarks | Ch 1–2 | Ch 1 | Ch 1 | Ch 1 | Ch 1 | Ch 1 | [`ch01_fundamentals`](../ch01_fundamentals/README.md) — **Partial** (1 example: `amdahl_speedup`) |
| Memory Hierarchy Design (Advanced) | Ch 8 (§§8.7–8.8) | Ch 5 | Ch 5 | Ch 5 | Ch 2 | Ch 2 | [`ch02_memory_hierarchy`](../ch02_memory_hierarchy/README.md) — **Partial** (7 examples) |
| Memory Hierarchy Review (Basics, 3Cs, Basic VM) | Ch 8 (§§8.1–8.6) | Ch 5 (§§5.1–5.3, 5.10–5.11) | Ch 5 (§§5.1–5.3, 5.10–5.11) | App C | App B | App B | [`ch02_memory_hierarchy`](../ch02_memory_hierarchy/README.md) — **Partial** (merged into Ch 2) |
| Advanced Address Translation | — | — | — | — | — | App L | **Missing** (no examples beyond basic `tlb_walker`; Appendix L missing from local text) |
| Instruction-Level Parallelism (Dynamic, Speculation) | Ch 6 (§§6.7–6.8) | Ch 3 | Ch 3 | Ch 2 | Ch 3 | Ch 3 | [`ch03_ilp`](../ch03_ilp/README.md) — **Partial** (5 examples; missing TAGE, RAS, SMT, Spectre/Meltdown) |
| Limits on ILP & Hardware Multithreading | — | — | Ch 3 (§3.8–3.11) / Ch 6 (§6.9) | Ch 3 | Ch 3 (§§3.10–3.12) | Ch 3 (§§3.10–3.11) | **Missing** (no ILP-limit or fine/coarse/SMT multithreading models) |
| VLIW, EPIC, and Software ILP | Ch 6 (§6.8), Ch 10 (§10.7) | Ch 4 | Ch 4 | App G (CD) | App H | App H | [`appH_vliw`](../appH_vliw/README.md) — **Partial** (1 example: `vliw4`) |
| Data-Level Parallelism (Vectors, SIMD, GPUs) | Ch 7 (Vectors) | App B/G | App G | App F (CD) | Ch 4 + App G | Ch 4 + App G | [`ch04_dlp`](../ch04_dlp/README.md) — **Partial** (4 examples; **App G** depth missing) |
| Thread-Level Parallelism (Snooping, Directory, Consistency) | Ch 10 (§§10.4, 10.8) | Ch 6 | Ch 6 | Ch 4 | Ch 5 | Ch 5 | [`ch05_tlp`](../ch05_tlp/README.md) — **Partial** (3 examples; missing consistency tests, LL/SC) |
| Large-Scale Multiprocessors & Scientific Apps | Ch 10 | Ch 6 + App I | App I | App H (CD) | App I | App I | **Missing** (no transient protocol races, MCS/tree locks, barriers, or HPC scaling models) |
| Warehouse-Scale Computers & Cloud (RLP) | — | — | Ch 8 (§§8.10–8.11) | Ch 6 (§6.7) | Ch 6 | Ch 6 | [`ch06_wsc`](../ch06_wsc/README.md) — **Guide only** (no RTL or Python models) |
| Domain-Specific Architectures | Ch 10 (§10.6) | — | — | — | — | Ch 7 | [`ch07_dsa`](../ch07_dsa/README.md) — **Partial** (1 example: TPU v1-style `systolic_array`) |
| Basic Processor Control (Hardwired & Microcode) | Ch 5 | — | — | — | — | — | **Missing** (1st Ed Ch 5 unpipelined datapath & microprogrammed control) |
| Pipelining: Basic & Intermediate Concepts | Ch 6 (§§6.1–6.6) | Ch 3 / App A | App A | App A | App C | App C | [`appC_pipelining`](../appC_pipelining/README.md) — **Partial** (2 examples; no exceptions/R4000/multicycle baseline) |
| Instruction Set Principles | Ch 3–4 | Ch 2 | Ch 2 | App B | App A | App A | **Missing** (no dedicated directory or examples) |
| Survey of Instruction Set Architectures | App B–E | App C–F | App C–F | App J (CD) | App K | App K | **Missing** (no compressed-ISA, CISC-vs.-RISC, or ISA-measurement examples) |
| Storage Systems & I/O | Ch 9 | Ch 6 | Ch 7 | Ch 6 | App D | App D | [`appD_storage`](../appD_storage/README.md) — **Minimal** (only SECDED + RAID-5; queueing, buses, DMA, RAID-6, Chipkill missing) |
| Embedded Systems & DSPs | — | — | Inline "Another View" (§§1.2, 2.13, 4.8, 5.14, 6.13, 7.13) | App D (CD) | App E | App E | **Missing** (no directory, no examples, not on roadmap) |
| Interconnection Networks | Ch 9 (§9.5), Ch 10 | Ch 7 | Ch 8 | App E (CD) | App F | App F | [`appF_interconnect`](../appF_interconnect/README.md) — **Partial** (4 examples; MINs, iterative arbiters, packet/bisection models missing) |
| Computer Arithmetic | App A | App H | App H | App I (CD) | App J | App J | [`appJ_arithmetic`](../appJ_arithmetic/README.md) — **Partial** (3 integer examples; all FP/IEEE-754/SRT/AI-formats missing) |
| Historical Perspectives & References | End of Ch 1–10, App A | End of Ch/App | End of Ch/App | App K (CD) | App L | App M | Out of scope for RTL (reference citations belong in `README.md` / `docs/editions.md`) |

*\*Note: Because the local `CA_2nd_Ed_1996.md` file contains 3rd-Edition content, 2nd-Edition (1996) positions follow [`docs/editions.md`](../docs/editions.md) notes rather than direct inspection of a 1996 file.*

---

## 5. Detailed Gap Analysis by Chapter and Appendix

### 5.1 Chapter 1 — Fundamentals of Quantitative Design and Analysis (1st Ed Ch 1–2)
- **Implemented:** [`amdahl_speedup`](../ch01_fundamentals/amdahl_speedup/README.md).
- **Planned in [`docs/roadmap.md`](../docs/roadmap.md):** performance counters / CPI-breakdown unit; dynamic-power estimator from toggle counts.
- **Still missing from both repository and roadmap:** IC wafer/die yield ($Y = Y_w (1 + d \cdot A / \alpha)^{-\alpha}$) and **7th Ed chiplet vs. monolithic cost/yield modeling** (§1.6); static leakage power, DVFS scaling curves, and **7th Ed operational vs. embodied carbon modeling** (§1.5); FIT rates, MTTF/MTTR, series/parallel availability (§1.7); AM/WAM/HM/GM/geometric-SD benchmark summarization and SPECPower (§1.8).

### 5.2 Chapter 2, Appendix B, and Appendix L — Memory Hierarchy Design & Address Translation
- **Implemented:** `set_assoc_cache`, `tlb_walker`, `victim_cache`, `stride_prefetcher`, `nonblocking_cache`, `writeback_nbcache`, `dram_controller`.
- **Planned in [`docs/roadmap.md`](../docs/roadmap.md):** separate prefetch stream buffer; store forwarding from write/write-back buffers; set-associative non-blocking caches.
- **Still missing from both repository and roadmap:** 3C miss classification (compulsory/capacity/conflict) and replacement policies (FIFO, Random, PLRU); advanced optimizations from §2.3 (way prediction, pipelined/multibanked caches, critical word first / early restart, VIPT cache aliasing); Flash/SSD FTL wear-leveling and HBM bandwidth/latency; **7th Ed Alloy Cache** (L4 DRAM Tag+Data with MAP-I hit/miss predictor) and **NUCA**; nested 2D virtualization page walks; **7th Ed cache timing side channels (`Prime+Probe`) and QoS way partitioning** (§2.4); **Appendix L** superpages, coalesced TLBs, page-walk caches, and TLB shootdowns.

### 5.3 Chapter 3 and Appendix H — ILP, Speculation, VLIW/EPIC, Limits on ILP, and Multithreading
- **Implemented:** `branch_predictor`, `scoreboard`, `tomasulo_rob`, `tomasulo_spec`, `tomasulo_lsq`, `vliw4`.
- **Planned in [`docs/roadmap.md`](../docs/roadmap.md):** history-table predictor in `tomasulo_spec`; memory-dependence speculation + replay in `tomasulo_lsq`; resolve-time recovery; tournament predictor + BTB; dual-issue in-order superscalar; software-pipelined DAXPY, predication, and delayed branches in `vliw4`.
- **Still missing from both repository and roadmap:** **TAGE** predictor and **Return Address Stack (RAS)** (§§3.3, 3.9); explicit **Physical Register File (PRF) + Rename Map Table (RMT)** renaming (§3.8); value prediction; **fine-grained, coarse-grained, and Simultaneous Multithreading (SMT)** (§§3.11–3.12); ILP limit sweeps (§3.10); **Spectre/Meltdown** transient-execution leakage + mitigation (§3.13); EPIC/IA-64 `ld.s`/`NaT` speculative loads, `ld.a`/ALAT advanced loads, and rotating registers (App H).

### 5.4 Chapter 4 and Appendix G — Data-Level Parallelism: Vectors, SIMD, and GPUs
- **Implemented:** `vector_lanes`, `vector_chaining`, `simd_alu`, `simt_core`.
- **Planned in [`docs/roadmap.md`](../docs/roadmap.md):** pack/unpack and shuffle for `simd_alu`; per-register scoreboard and memory coalescing for `simt_core`.
- **Still missing from both repository and roadmap:** **Appendix G** multi-banked vector memory bank conflicts under stride, gather/scatter indexed unit, dynamic strip-mining (`vsetvli` / `VL`), and $R_\infty / N_{1/2} / N_v$ performance models; GPU shared-memory (`__shared__`) bank conflicts and `__syncthreads()` barriers; **Roofline** arithmetic-intensity model (§4.3–4.4, §4.7); loop-dependence GCD/recurrence analysis (§4.5).

### 5.5 Chapter 5 and Appendix I — Thread-Level Parallelism and Large-Scale Multiprocessors
- **Implemented:** `mesi_snoopy`, `directory_msi`, `spinlock_atomic`.
- **Planned in [`docs/roadmap.md`](../docs/roadmap.md):** memory-consistency litmus tests; LL/SC, exponential back-off locks, and barriers; directory cache replacements and limited-pointer/coarse-vector sharing.
- **Still missing from both repository and roadmap:** **MOESI / MESIF** protocols, 4th-C coherence miss breakdown (true vs. false sharing), and multilevel inclusion back-invalidation (§§5.2–5.3); **Appendix I** non-atomic split-transaction coherence with transient states (`IM`/`SM`/`MI`) and bus/directory race handling (§I.7); **MCS queue locks** and **combining-tree / sense-reversing barriers** (§I.4); store-buffer/fence consistency enforcement; HPC kernel communication scaling (§I.3, §I.5) and Power10 / Xeon Platinum / Blue Gene/L NUMA topologies.

### 5.6 Chapter 6 — Warehouse-Scale Computers & Request-Level Parallelism
- **Implemented:** None (guide-only [`ch06_wsc/README.md`](../ch06_wsc/README.md)).
- **Planned in [`docs/roadmap.md`](../docs/roadmap.md):** Python queueing / tail-latency / PUE model.
- **Still missing from both repository and roadmap:** fan-out tail latency + **hedged/tied requests**; WSC memory/storage hierarchy modeling; **Clos/fat-tree oversubscription and Google Jupiter Optical Circuit Switching (OCS)**; CAPEX/OPEX TCO and carbon-aware 4M modeling; Meta server/JBOF architecture; and **AWS Nitro DPU offload + Graviton3 chiplet** cloud virtualization.

### 5.7 Chapter 7 — Domain-Specific Architectures
- **Implemented:** `systolic_array` (TPU v1 int8 weight-stationary).
- **Planned in [`docs/roadmap.md`](../docs/roadmap.md):** convolution line-buffer engine; activation + quantization stage; output-stationary variant.
- **Still missing from both repository and roadmap:** 6th-Ed **Catapult** FPGA torus, **Pixel Visual Core** 2D stencil + Halo, and **Crest**; 7th-Ed **TPU v4 / v4 lite** (4D Tensor DMA, VLIW CMEM, 3D torus ICI), **NVIDIA Tensor Cores** ($4\times4\times4$ MMA, **2:4 structured sparsity**, **Transformer Engine** `fp8`/`fp16` dynamic scaling, `bf16`/`tf32`/`fp8`/`fp4`), **Graphcore Bow IPU** BSP model, **Samsung NPUv1/v2** input sparsity, **MLPerf** latency-bounded/thermal models, and **4M sustainability** framework.

### 5.8 Appendices A & K — Instruction Set Principles & Survey of ISAs
- **Implemented & Planned:** None (outside cross-cutting DLX/MIPS64 pipeline variants).
- **Still missing:** ISA taxonomy comparators (stack/accumulator/reg-mem/load-store); compressed **RV32IC/RV64GC / Thumb-2 / microMIPS** 16→32-bit instruction expander (App K.2); variable-length prefix decoding; scaled/auto-increment addressing and unaligned access alignment; 1st-Ed instruction frequency vs. time-distribution analysis.

### 5.9 Appendix C (and 1st Ed Ch 5) — Basic Processor Implementation & Pipelining
- **Implemented:** `rv32i_pipeline5`, `mips_pipeline5`.
- **Planned:** unpipelined multicycle baseline; pipelined FPU; delayed-branch `mips_pipeline5`.
- **Still missing:** **1st Ed Ch 5** hardwired FSM vs. microprogrammed ROM/sequencer control; **precise pipeline exceptions** (`MRET`/`ERET`, MEM fault vs. EX overflow priority); **MIPS R4000 8-stage superpipeline** (2-cycle load, 3-cycle branch delay).

### 5.10 Appendix D — Storage Systems and I/O
- **Implemented:** `hamming_secded`, `raid5_parity`.
- **Planned:** None.
- **Still missing:** $M/M/1$, $M/G/1$, $M/M/m$ queueing models and Little's Law; **RAID-6 dual-parity ($P+Q$)** and **Chipkill DRAM ECC**; split-transaction I/O bus handshakes, **DMA descriptor engine**, and **I/O-cache coherence**; disk seek/rotational/SSD models and empirical failure-rate simulators.

### 5.11 Appendix E — Embedded Systems and DSPs
- **Implemented & Planned:** None.
- **Still missing:** **DSP Q-format fixed-point MAC** with guard bits and hardware saturation; **circular (modulo) and bit-reversed address generators**; **zero-overhead hardware loop controller**; scratchpad vs. cache predictability and EEMBC/Embench power-performance comparison.

### 5.12 Appendix F — Interconnection Networks
- **Implemented:** `rr_crossbar`, `mesh_router`, `vc_router`, `torus_dateline`.
- **Planned:** adaptive (west-first) routing; speculative single-cycle VA+SA.
- **Still missing:** **Multistage Interconnection Networks (Omega / Butterfly / Fat-Tree / Clos)** with $2\times2$ switches and XOR self-routing; OCN/SAN/LAN/WAN latency & bisection-bandwidth analytical models; **3-phase / iSLIP iterative switch arbiters**; **Xon/Xoff vs. credit** flow control and **store-and-forward vs. virtual cut-through vs. wormhole** comparison; **protocol deadlock** (separate request/reply VNs).

### 5.13 Appendix J — Computer Arithmetic
- **Implemented:** `carry_lookahead_adder`, `booth_multiplier`, `restoring_divider`.
- **Planned:** IEEE 754 adder / multiplier / FMA; SRT divider.
- **Still missing:** **carry-skip**, **carry-select**, **carry-save (CSA) / Wallace-tree** multipliers, and non-restoring division; **radix-4 SRT P-D table** with **Pentium FDIV bug** demonstration; full IEEE-754 guard/round/sticky rounding modes, subnormals, NaNs, and exception flags; **`bf16`, `tf32`, `fp16`, `fp8` (E4M3/E5M2), `fp4`** ML arithmetic units.

---

## 6. Concrete Work-Item Backlog & Module Specifications (Agent Execution Queue)

Each item below gives an implementing agent a deterministic path, source citation, RTL/Python specification, and self-checking verification contract. Items marked `[Roadmap]` already appear in [`docs/roadmap.md`](../docs/roadmap.md); items marked `[New Gap]` fill unscheduled textbook sections.

### 6.1 Chapter 1 (`ch01_fundamentals`)
| ID | Target path | Textbook source | Implementation spec (SV + VHDL or Python) | Verification & pass invariant |
|---|---|---|---|---|
| `CH01-1` `[Roadmap]` | `ch01_fundamentals/cpi_power_counters` | 5th–7th Ed §§1.5, 1.8–1.9; 1st Ed §2.2 | `cpi_power_counters` RTL module monitoring retired instructions by class (ALU/load/store/branch), stall cycles (structural/data/control/L1-miss), and dynamic toggle-activity bit transitions (`P_dyn = 0.5*C*V^2*f*alpha`, `P_stat = I_stat*V`). Outputs exact cycle/CPI counters and Q16.16 energy/power estimates. | Drive two synthetic instruction+stall traces (baseline vs. reduced-stall / clock-gated); assert `CPI = (cycles_busy + cycles_stall)/inst_retired` and check >= 30% dynamic energy reduction under clock-gating against Python golden model. |
| `CH01-2` `[New Gap]` | `ch01_fundamentals/python/quant_eval_suite.py` | 5th–7th Ed §§1.5–1.8; 7th Ed §1.6 (chiplets, carbon) | Stdlib Python 3 module + `unittest` suite implementing: (a) dies-per-wafer & Bose-Einstein die yield + monolithic vs. 4-chiplet cost model; (b) series/parallel MTTF, MTTR, FIT, and availability; (c) DVFS voltage-frequency cubic power vs. energy-delay; (d) operational + embodied carbon; (e) AM/WAM/HM/GM + geometric SD. | Assert exact closed-form test vectors (including 7th-Ed dual-power-supply reliability gain and chiplet-vs.-monolithic break-even defect density). |

### 6.2 Chapter 2, Appendix B & Appendix L (`ch02_memory_hierarchy` / `appL_translation`)
| ID | Target path | Textbook source | Implementation spec (SV + VHDL) | Verification & pass invariant |
|---|---|---|---|---|
| `CH02-1` `[Roadmap]` | `ch02_memory_hierarchy/stream_buffer` | 5th–7th Ed §2.3 (prefetching); Jouppi 1990 | Separate 4-entry FIFO **prefetch stream buffer** sitting below a direct-mapped L1 cache (`set_assoc_cache` or internal L1): miss probes buffer head; hit pops into L1 and triggers `N+1` lookahead refill; miss flushes and allocates sequential stream. | Compare sequential + interleaved-stream traces with stream buffer off vs. on; assert compulsory/sequential miss reduction >= 70% and identical cycle counts in SV and VHDL. |
| `CH02-2` `[Roadmap]` | `ch02_memory_hierarchy/nb_set_assoc_cache` | 5th–7th Ed §2.3 (non-blocking, write-back) | 2-way or 4-way set-associative **non-blocking write-back cache** with 4 MSHRs, LRU replacement, and a **store-forwarding write-back buffer** (reads hit pending evicted/write-buffer lines before DRAM). | Test hit-under-miss, miss-under-miss, secondary misses to same line, and load hitting a pending write-back buffer entry; compare against independent Python cycle/data model. |
| `CH02-3` `[New Gap]` | `ch02_memory_hierarchy/cache_3c_policies` | 5th–7th Ed §B.3 (3Cs), Fig. B.8; 1st Ed §8.7 | Parameterizable cache-policy evaluator supporting `ASSOC=1..4` and replacement policy `POLICY` (`LRU`, `FIFO`, `RANDOM`/LFSR, `PLRU`), plus a reference infinite/fully-associative shadow tracker classifying every miss into **compulsory**, **capacity**, or **conflict**. | Run 256-access thrashing, capacity-overflow, and working-set traces; assert exact 3C miss totals satisfy `total = compulsory + capacity + conflict` and `conflict(4-way) < conflict(1-way)`. |
| `CH02-4` `[New Gap]` | `ch02_memory_hierarchy/way_predict_vipt` | 5th–7th Ed §2.3 (way prediction, multibanked, VIPT, CWF) | 2-way set-associative L1 implementing (a) **way prediction** (MRU prediction bit: 1-cycle fast hit vs. 2-cycle secondary-way probe), (b) **critical-word-first + early restart** refill, and (c) **VIPT page-coloring** index check preventing synonyms when `index_bits <= page_offset_bits`. | Verify 1-cycle vs. 2-cycle hit energy/latency breakdown, CWF early completion before full line refill finishes, and zero synonym corruption across aliased virtual addresses. |
| `CH02-5` `[New Gap]` | `ch02_memory_hierarchy/alloy_dram_cache` | 7th Ed §2.3, Fig. 2.16, Ex. 2.28–2.29 | L4 **Alloy Cache** controller modeling a direct-mapped DRAM cache storing **Tag+Data (TAD)** in one burst alongside a **1-cycle MAP-I hit/miss predictor** that speculatively launches backing-memory fetch in parallel on predicted miss. | Compare baseline tag-then-data serial Alloy Cache vs. MAP-I predicted parallel miss on 80%/15%/5% trace profile; assert average latency matches exact analytical equation. |
| `CH02-6` `[New Gap]` | `ch02_memory_hierarchy/prime_probe_qos` | 7th Ed §2.4, Ex. 2.26, 2.31 | Shared 4-way LLC with `domain_id` (`victim=0`, `spy=1`) demonstrating a **Prime+Probe timing side-channel** when unpartitioned (`qos_partition_en=0`) vs. hardware **way partitioning** (`qos_partition_en=1`) isolating victim/spy ways. | Run spy prime → victim secret-dependent access → spy probe; assert spy observes >= 1 miss when `qos_partition_en=0` (secret bit inferred) and 0 interference misses when `qos_partition_en=1`. |
| `CH02-7` `[New Gap]` | `ch02_memory_hierarchy/nested_pt_walker` *(or `appL_translation/`)* | 5th–7th Ed §2.4; 6th–7th Ed App L | 2-level guest-VA → guest-PA → host-PA **nested 2D hardware page-table walker** with **page-walk cache (PWC)** and **superpage (4 KiB vs. 2 MiB) + ASID TLB** support. (`deps.txt` can inspect `tlb_walker` conventions.) | Verify exact memory-reference amplification (nested $2\times2$ or $4\times4$ walk steps without PWC vs. reduced steps with PWC, superpage hit collapsing multiple 4 KiB misses, and ASID isolation without flush). |

### 6.3 Chapter 3 & Appendix H (`ch03_ilp`, `appH_vliw`)
| ID | Target path | Textbook source | Implementation spec (SV + VHDL) | Verification & pass invariant |
|---|---|---|---|---|
| `CH03-1` `[Roadmap]` | `ch03_ilp/tournament_btb_ras` | 5th–7th Ed §3.3, §3.9 | 2-bit/global/local **Tournament Branch Predictor** (with 2-bit selector table) + direct-mapped **Branch Target Buffer (BTB)** + 4-entry **Return Address Stack (RAS)** for `CALL`/`RET` target prediction. | Compare local-only, global-only, and tournament accuracy on alternating correlated + periodic branches, plus 100% `RET` target hit rate on nested calls up to depth 4. |
| `CH03-2` `[New Gap]` | `ch03_ilp/tage_predictor` | 6th–7th Ed §3.3 | **TAGE (TAgged GEometric history length) branch predictor**: bimodal base table + 3 geometrically sized tagged history tables ($L = 2, 6, 18$) with partial tags, useful counters (`u`), and longest-match selection. | Compare TAGE vs. gshare on long-history correlated branches ($L=16$ pattern); assert TAGE eliminates aliasing mispredictions and matches independent Python TAGE model cycle-for-cycle. |
| `CH03-3` `[Roadmap]` | `ch03_ilp/superscalar_dual_issue` | 5th–7th Ed §3.7 | **Dual-issue static in-order 5-stage superscalar** core (1 ALU/branch slot + 1 ALU/load-store slot per 64-bit packet) with cross-slot RAW dependency checker, dual-issue forwarding, and load-use stalling. | Run loop-unrolled DAXPY/dot-product vs. unscheduled scalar trace; assert IPC > 1.5 and identical architectural register/memory state to `rv32i_pipeline5`. |
| `CH03-4` `[Roadmap]` | `ch03_ilp/tomasulo_mem_spec_replay` | 5th–7th Ed §3.6, §3.9 | Extend `tomasulo_lsq` (`deps.txt: ch03_ilp/tomasulo_lsq` or standalone copy) with **speculative load bypassing** past unresolved store addresses, store-alias violation detection on store address resolution, and **ROB/LSQ selective replay** + **resolve-time branch recovery**. | Run independent load-behind-unknown-store (saves 3+ cycles vs. conservative LSQ) AND aliasing load-behind-store (triggers violation squash/replay and produces correct forwarded value). |
| `CH03-5` `[New Gap]` | `ch03_ilp/prf_rename_ooo` | 5th–7th Ed §3.8 (Core i7 / P6 style) | Out-of-order engine using an explicit **Physical Register File (PRF)**, **Frontend & Architectural Register Map Tables (RMT)**, **Free List**, and pointer-only ROB (values live in PRF, not ROB slots), freeing old physical registers at commit and rolling back RMT on branch mispredict. | Stress WAW/WAR chains larger than architectural register count; verify free-list conservation (`free + active == PRF_SIZE` after drain) and exact RMT recovery on flush. |
| `CH03-6` `[New Gap]` | `ch03_ilp/smt_multithread_core` | 4th Ed §3.5; 5th–7th Ed §3.11 | 2-thread dual-issue core configurable across `MODE` = `SINGLE`, `COARSE_MT`, `FINE_MT` (barrel/interleaved), and `SMT` (simultaneous issue from two independent thread fetch/rename queues sharing 2 ALU + 1 Mem execution pipes). | Run two traces with long memory/mul stalls; assert `IPC(SMT) > IPC(FINE_MT) > IPC(COARSE_MT) > IPC(SINGLE)` while preserving per-thread architectural outputs. |
| `CH03-7` `[New Gap]` | `ch03_ilp/spectre_transient_demo` | 6th–7th Ed §3.13 (Spectre/Meltdown pitfall) | Speculative bounds-check + dependent cache-line load micro-demo: when `mitigation_en=0`, a wrong-path bounds-check misprediction loads `secret[idx]` and caches `probe[val]` before ROB squash; when `mitigation_en=1` (speculation barrier / taint-delay), the transient cache fill is blocked. | Verify architectural registers match in both modes, while probe-cache hit timing reveals `secret` when `mitigation_en=0` and reveals nothing (all probe misses) when `mitigation_en=1`. |
| `APPH-1` `[Roadmap+Gap]` | `appH_vliw/vliw4_swpipe_pred_alat` | 5th–7th Ed App H.3–H.5 | Extended 4-slot VLIW supporting **if-conversion predicate registers (`p0..p7`)**, **non-faulting speculative loads (`ld.s`) + `NaT` poison bit propagation + `chk.s`**, **advanced loads (`ld.a`) + 4-entry ALAT**, and **software-pipelined modulo loop scheduling** (prologue/kernel/epilogue). | Verify software-pipelined DAXPY beats loop-unrolled `vliw4` IPC; verify `ld.s` on faulting address suppresses trap unless `chk.s` executes on taken path; verify `ld.a` detects store collision in ALAT. |

### 6.4 Chapter 4 & Appendix G (`ch04_dlp`)
| ID | Target path | Textbook source | Implementation spec (SV + VHDL) | Verification & pass invariant |
|---|---|---|---|---|
| `CH04-1` `[Roadmap]` | `ch04_dlp/simd_pack_shuffle` | 5th–7th Ed §4.3 (`simd_alu` extension) | Subword **pack/unpack** (int32→int16→int8 with saturation/zero-extend) and **shuffle/permute** (`PSHUFB`-style byte/halfword crossbar) unit (`deps.txt` optional or standalone). | Test 8x8 matrix transpose and int32-to-int8 saturating quantization kernels against Python golden vectors. |
| `CH04-2` `[Roadmap+Gap]` | `ch04_dlp/simt_coalesce_bankconflict` | 5th–7th Ed §4.4 | GPU SM memory + register scoreboard extension for `simt_core`: (a) **per-warp register scoreboard** preventing RAW hazards across warps, (b) **global memory coalescer** merging 8/16/32 lane addresses into minimal 64-byte cache-line transactions, and (c) **32-bank shared memory** detecting/serializing $k$-way bank conflicts + `__syncthreads()` barrier. | Assert coalesced stride-1 warp takes 1 global transaction vs. $N$ transactions for stride-16; assert 4-way shared-memory bank conflict takes 4 replay cycles vs. 1 cycle conflict-free. |
| `CH04-3` `[New Gap]` | `ch04_dlp/vector_bank_gather_strip` | 5th–7th Ed §4.2 & App G.2–G.4; 1st Ed Ch 7 | Multi-banked vector memory + **strip-mining (`vsetvli`)** controller: 8 SRAM banks with configurable stride, **gather/scatter** indexed load/store FSM, and hardware strip-mining loop processing arbitrary $n > \text{MVL}$ vectors; measures chimes, $R_\infty$, $N_{1/2}$, and bank-conflict stalls. | Assert unit-stride (`stride=1`) achieves 0 bank stalls, `stride=8` hits 8-way bank conflict (8x stall), gather/scatter preserves sparse array semantics, and `n=45` (`MVL=16`) processes `16+16+13` cleanly. |
| `CH04-4` `[New Gap]` | `ch04_dlp/python/roofline_loop_model.py` | 5th–7th Ed §§4.3–4.5, 4.7 | Stdlib Python 3 **Roofline + loop-dependence analyzer**: computes ridge point, memory-bound vs. compute-bound ceilings across vector/SIMD/GPU targets, and implements the **GCD dependence test** for affine loop nests (`a*i + b = c*j + d`). | Verify Roofline ceilings against 5th/6th/7th-Ed Core i7 vs. GPU kernel examples and pass unit tests on loop-carried dependence classification. |

### 6.5 Chapter 5 & Appendix I (`ch05_tlp`)
| ID | Target path | Textbook source | Implementation spec (SV + VHDL) | Verification & pass invariant |
|---|---|---|---|---|
| `CH05-1` `[Roadmap]` | `ch05_tlp/consistency_litmus_tsosb` | 5th–7th Ed §5.6 | 2-core memory-consistency subsystem with configurable **per-core FIFO store buffer**, drain/flush control, and `FENCE` instruction running canonical **Store-Buffering (`SB`)** and **Message-Passing (`MP`)** litmus tests under Sequential Consistency (`SC`) vs. Total Store Order (`TSO`). | Assert `SB` can observe `(r1=0, r2=0)` under `TSO` without `FENCE`, and **never** observes `(0,0)` under `SC` or when `FENCE` drains the store buffer. |
| `CH05-2` `[Roadmap]` | `ch05_tlp/llsc_backoff_barrier` | 5th–7th Ed §5.5; App I.4 | 4-core snooping-bus synchronization unit implementing **Load-Linked / Store-Conditional (`LR`/`SC`)** link-register invalidation, **exponential back-off TTAS spinlock**, and **sense-reversing barrier**. | Verify `SC` fails when an intervening remote store invalidates the reservation; assert exponential back-off cuts bus invalidations vs. plain TAS/TTAS; verify 2 consecutive barrier phases do not deadlock. |
| `CH05-3` `[Roadmap]` | `ch05_tlp/directory_limited_evict` | 5th–7th Ed §5.4 | Extend directory MSI to support **cache block eviction/replacement** (`PutS`/`PutM` write-backs to directory) and configurable directory storage modes: **full bit-vector** vs. **limited-pointer (`Dir_iB` broadcast fallback)** vs. **coarse bit-vector**. | Verify replacement of shared/modified lines leaves directory and memory consistent, and compare invalidation message counts across full, `Dir_2B`, and coarse modes. |
| `CH05-4` `[New Gap]` | `ch05_tlp/moesi_false_sharing` | 5th–7th Ed §§5.2–5.3 | 4-core **MOESI snooping cache** (Owned state supplies dirty cache-to-cache data without immediate DRAM write-back) with hardware miss-classifier tagging every miss as **Cold/Capacity/Conflict** vs. **True Sharing** vs. **False Sharing** (different word in same cache block). | Verify cache-to-cache dirty read hits `O` state with 0 memory writes; verify two cores writing adjacent words (`addr+0`, `addr+1`) trigger `false_sharing_misses > 0` until padded to separate cache lines. |
| `CH05-5` `[New Gap]` | `ch05_tlp/split_bus_transient_msi` | 5th–7th Ed App I.7 (3rd Ed App I.1–I.2) | Non-atomic **split-transaction snooping coherence controller** implementing explicit **transient states** (`I->M` `IM_AD`/`IM_D`, `S->M` `SM_AD`, `M->I` `MI_A`) and NACK/retry or bus-order serialization under simultaneous dual-core upgrade races. | Inject same-cycle `ReadX` upgrades from Core 0 and Core 1 to the same line; verify one core wins cleanly, the losing core observes the winner's invalidation in transient state, and final data matches sequential consistency without deadlock or stale reads. |
| `CH05-6` `[New Gap]` | `ch05_tlp/mcs_combining_barrier` | 5th–7th Ed App I.4 | Hardware/memory-model demonstration comparing a **combining-tree barrier** vs. centralized counter barrier and **MCS queue-based spinlock** (each core spins on its own local cache line) across 8 simulated nodes. | Assert remote interconnect transactions per lock handoff drop from $O(N)$ (centralized spinlock) to $O(1)$ (MCS) and barrier traffic scales logarithmically with combining tree. |

### 6.6 Chapter 6 (`ch06_wsc`)
| ID | Target path | Textbook source | Implementation spec | Verification & pass invariant |
|---|---|---|---|---|
| `CH06-1` `[Roadmap+Gap]` | `ch06_wsc/python/wsc_model_suite.py` | 5th–7th Ed §§6.1–6.7 | Stdlib Python 3 analytical/discrete-event suite + `unittest` covering: (a) fan-out tree query **tail latency** + **hedged/tied request** reduction; (b) **WSC memory/storage latency-bandwidth hierarchy**; (c) **PUE**, **CAPEX/OPEX TCO** (server amortization, $/W facility, energy proportionality); and (d) **operational + embodied carbon (4M)**. | Verify exact closed-form PUE/TCO numbers (matching 6th/7th-Ed Google case study formulas) and assert hedged requests cut 99th-percentile tail latency on synthetic heavy-tailed service distributions. |
| `CH06-2` `[New Gap]` | `ch06_wsc/clos_ocs_fabric` | 7th Ed §6.4 (Clos + Google Jupiter OCS) | RTL 8-leaf x 4-spine **Clos + reconfigurable Optical Circuit Switch (OCS) fabric** (SV + VHDL): dynamically switches spine-to-leaf link counts (`2x2` OCS crossbar schedules) to adapt bisection bandwidth between uniform and skewed rack-pair traffic. | Compare static 2:1 oversubscribed Clos vs. OCS-reconfigured topology under skewed rack traffic; assert zero dropped packets and >= 1.5x throughput gain for hot rack pairs. |

### 6.7 Chapter 7 (`ch07_dsa`)
| ID | Target path | Textbook source | Implementation spec (SV + VHDL) | Verification & pass invariant |
|---|---|---|---|---|
| `CH07-1` `[Roadmap]` | `ch07_dsa/conv2d_linebuffer` | 6th–7th Ed §7.3 (CNNs) | Streaming **$3 \times 3$ 2D convolution engine** using 2 shift-register **line buffers** and a $3 \times 3$ sliding window of int8 MACs (`1 pixel/cycle` steady-state throughput). | Stream a $16 \times 16$ image + kernel; compare every valid output pixel against Python 2D reference convolution. |
| `CH07-2` `[Roadmap]` | `ch07_dsa/systolic_os_act_quant` | 6th–7th Ed §§7.3–7.4 | **Output-stationary** $4 \times 4$ systolic array (partial sums stay in PE accumulators while A/B stream orthogonally) followed by a vectorized **ReLU / ReLU6 + bias + shift/clamp int32→int8 quantization** post-processor. | Verify output-stationary GEMM + bias + ReLU + int8 requantization matches Python fixed-point DNN layer golden output across positive and negative inputs. |
| `CH07-3` `[New Gap]` | `ch07_dsa/tensor_core_sparse24_fp8` | 7th Ed §§7.4–7.5 (Volta/Ampere/Hopper Tensor Cores) | TPU/GPU-style **$4 \times 4$ Tensor Core MMA (`D = A*B + C`)** supporting **2:4 structured sparsity** (2-bit index mask compresses 4 weights to 2 non-zero values, doubling throughput) and **bf16/fp8-with-scale → fp32 accumulation** (modeling Hopper Transformer Engine precision scaling). | Verify dense `bf16` MMA and compressed 2:4 sparse MMA produce identical `D` to dense Python reference while cutting weight memory reads and cycles by 2x. |
| `CH07-4` `[New Gap]` | `ch07_dsa/stencil_halo_2d` | 6th Ed §7.7 (Pixel Visual Core) | 2D $4 \times 4$ SIMD **stencil processor array** with programmable **1-pixel Halo neighbor exchange** (N/S/E/W shifts) and local line buffer executing Sobel/box filters on local scratchpad tiles without off-chip refetches. | Verify halo boundary clamping/wrapping and exact Sobel filter output on an $8 \times 8$ tile with zero redundant DRAM fetches. |

### 6.8 Appendices A & K (`appA_isa` — new group directory)
| ID | Target path | Textbook source | Implementation spec (SV + VHDL) | Verification & pass invariant |
|---|---|---|---|---|
| `APPA-1` `[New Gap]` | `appA_isa/rvc_compressed_decoder` | 6th–7th Ed App A, App K.2 | **RISC-V RVC (`RV32IC`) 16-bit → 32-bit instruction expander** (handling `C.ADDI`, `C.LW`, `C.SW`, `C.BEQZ`, `C.J`, `C.JAL`, `C.MV`, `C.ADD`, plus 32-bit pass-through) with variable-increment 16/32-bit fetch buffer feeding `rv32i_pipeline5` (`deps.txt` optional) or standalone decoder verification. | Verify 100% bit-exact expansion against RV32I encodings and execute a mixed 16/32-bit loop demonstrating ~25–30% static/dynamic code-size reduction. |
| `APPA-2` `[New Gap]` | `appA_isa/python/isa_class_traffic.py` | 1st Ed Ch 3–4, App C–D; 5th–7th Ed App A | Stdlib Python 3 ISA simulator comparing **Stack**, **Accumulator**, **Register-Memory**, and **Load-Store (RISC-V/MIPS64)** encodings executing the same expression/sort kernels; reports instruction count, encoded code bytes, and memory-operand data bytes. | Assert exact instruction-count and byte-traffic ratios matching textbook Class A/B/C/D comparisons. |

### 6.9 Appendix C (`appC_pipelining`)
| ID | Target path | Textbook source | Implementation spec (SV + VHDL) | Verification & pass invariant |
|---|---|---|---|---|
| `APPC-1` `[Roadmap+Gap]` | `appC_pipelining/multicycle_microcode_baseline` | 1st Ed Ch 5 (§§5.3–5.7); 5th–7th Ed App C.1 | Non-pipelined **multi-cycle RV32I (or DLX) CPU** selectable between **hardwired FSM control** and **microprogrammed ROM + micro-PC sequencer** (`4–5 cycles/inst`), sharing the exact same test program as `rv32i_pipeline5`. | Run the `rv32i_pipeline5` test program; assert identical final registers/memory and measured CPI speedup (`CPI_multicycle / CPI_pipeline >= 2.5x`), plus exact cycle parity between hardwired and microprogrammed modes. |
| `APPC-2` `[New Gap]` | `appC_pipelining/rv32i_precise_exceptions` | 5th–7th Ed App C.4; 1st Ed §6.5 | Extend `rv32i_pipeline5` (`deps.txt` or variant) with **precise synchronous/asynchronous exceptions**: IF/MEM address fault, ID illegal opcode, EX arithmetic/ecall, stage-priority resolution (oldest instruction wins), `MEPC`/`MCAUSE` CSRs, pipeline flush, and `MRET` resume. | Trigger simultaneous exceptions in MEM (older) and EX (younger); verify MEM exception wins, younger instructions never update architectural state, handler runs, and `MRET` resumes cleanly. |
| `APPC-3` `[Roadmap+Gap]` | `appC_pipelining/r4000_superpipeline8` | 5th–7th Ed App C.6; 4th Ed App A.6 | **8-stage MIPS64/DLX superpipeline** (`IF`, `IS`, `RF`, `EX`, `DF`, `DS`, `TC`, `WB`) demonstrating **2-cycle load-use delay** and **3-cycle branch delay** (plus delayed-branch option) and optional pipelined FP unit (`App A/C` roadmap). | Run dependent load-use and branch traces against 5-stage `mips_pipeline5`; verify exact CPI penalty increase (`2` load-stall cycles and `3` branch-flush cycles) with identical final register state. |

### 6.10 Appendix D (`appD_storage`)
| ID | Target path | Textbook source | Implementation spec | Verification & pass invariant |
|---|---|---|---|---|
| `APPD-1` `[New Gap]` | `appD_storage/raid6_p_q_chipkill` | 5th–7th Ed App D.2, Ch 2 Ex. 2.25 | Hardware (SV + VHDL) **RAID-6 $P+Q$ Galois-field $\text{GF}(2^8)$ dual-parity encoder/reconstructor** (survives **2 simultaneous failed disks**) paired with a **Chipkill ECC (`Symbol-ECC` over $\times 4$ DRAM nibbles)** encoder/corrector recovering an entire failed 4-bit DRAM chip. | Inject all single- and dual-disk erasure pairs (including data+data, data+P, data+Q, P+Q) and all 4-bit DRAM nibble faults; verify 100% bit-exact data recovery. |
| `APPD-2` `[New Gap]` | `appD_storage/dma_split_bus_coherence` | 1st Ed §§9.5–9.7; 3rd Ed §7.3 | **Descriptor-driven DMA controller + CPU snooped/non-snooped memory bus**: supports burst transfers between peripheral FIFO and memory, completion IRQ, and selectable **hardware I/O cache snooping** vs. stale-cache hazard mode. | Demonstrate cache-stale failure when DMA writes memory without snooping/flush, and 100% coherent CPU readback when hardware snooping invalidates stale cache lines. |
| `APPD-3` `[New Gap]` | `appD_storage/python/io_queueing_unit.py` | 5th–7th Ed App D.4–D.5; 4th Ed §§6.4–6.5 | Stdlib Python 3 queueing & reliability calculator + `unittest` implementing Little's Law, $M/M/1$, $M/G/1$ (Pollaczek-Khinchine), $M/M/m$, disk seek/rotation/transfer (`seek = a + b*sqrt(d)`), and RAID-5/6 rebuild-window data-loss probability (`AFR`, `MTTR`). | Verify textbook App D.5 worked queueing examples (response time vs. utilization knee) and RAID rebuild MTTDL calculations to `< 1e-9` relative error. |

### 6.11 Appendix E (`appE_embedded` — new group directory)
| ID | Target path | Textbook source | Implementation spec (SV + VHDL) | Verification & pass invariant |
|---|---|---|---|---|
| `APPE-1` `[New Gap]` | `appE_embedded/dsp_qmac_circular_zoloop` | 5th–7th Ed App E.2 | Fixed-point **DSP MAC datapath + address/loop unit**: `Q1.15 x Q1.15 -> 40-bit` guard-bit accumulator with **hardware saturation + convergent rounding**, **circular (modulo-$N$) pointer unit** (FIR delay line), **bit-reversed address generator** (16-point radix-2 FFT), and **zero-overhead hardware `RPT` loop counter**. | Execute a 16-tap FIR filter (zero loop-branch overhead + wrap-around circular buffer + saturation under overflow) and verify bit-reversed permutation sequence against Python reference. |

### 6.12 Appendix F (`appF_interconnect`)
| ID | Target path | Textbook source | Implementation spec (SV + VHDL) | Verification & pass invariant |
|---|---|---|---|---|
| `APPF-1` `[Roadmap]` | `appF_interconnect/west_first_adaptive_spec_vc` | 5th–7th Ed App F.5–F.6 | `4x4` mesh router (`deps.txt: appF_interconnect/vc_router` or standalone) adding (a) **West-First minimal adaptive routing** (deadlock-free turn model routing West before E/N/S, choosing less-congested NE/SE output) and (b) **speculative single-cycle VA+SA** pipeline (`1` router hop cycle unloaded instead of `2`). | Demonstrate 100% deadlock-free delivery under hotspot traffic (bypassing congested link via adaptive path) and verify unloaded hop latency matches speculative 1-cycle pipeline timing. |
| `APPF-2` `[New Gap]` | `appF_interconnect/omega_fat_tree_islip` | 5th–7th Ed App F.4, F.6 | **8x8 3-stage Omega / Butterfly MIN** built from $2\times2$ wormhole/credit switches with XOR bit-routing alongside a **3-phase / iterative `iSLIP` separable switch arbiter** (`request -> grant -> accept`). | Test permutation (uniform) vs. bit-reversal/transpose (blocking) traffic on Omega network; verify iterative `iSLIP` achieves higher crossbar utilization than 2-phase single-iteration RR arbitration. |

### 6.13 Appendix J (`appJ_arithmetic`)
| ID | Target path | Textbook source | Implementation spec (SV + VHDL) | Verification & pass invariant |
|---|---|---|---|---|
| `APPJ-1` `[New Gap]` | `appJ_arithmetic/csa_wallace_skip_select` | 5th–7th Ed App J.8–J.9 | Parameterizable integer datapath comparing **16-bit Carry-Skip Adder**, **16-bit Carry-Select Adder**, and **$8 \times 8$ Wallace-Tree Carry-Save Adder (CSA) Multiplier** against a ripple baseline, reporting simulated logic-level delay / gate-count proxy. | Exhaustively test all 65,536 $8\times8$ products and edge carry-chain vectors; verify bit-exact equality with `+` and `*`. |
| `APPJ-2` `[Roadmap+Gap]` | `appJ_arithmetic/srt4_divider_fdiv` | 5th–7th Ed App J.6, J.9 (Fig. J.33, J.35) | **Radix-4 SRT divider** (redundant quotient set $\{-2,-1,0,1,2\}$, carry-save partial remainder, P-D plot quotient-selection lookup table, on-the-fly quotient conversion) with an optional fault-injection parameter `PENTIUM_FDIV_BUG=1` reproducing the 5 omitted PD-table entries. | Verify 2 bits/cycle quotient retirement and 100% exact division/remainder across random + boundary vectors when `PENTIUM_FDIV_BUG=0`; verify known affected dividend/divisor pair (`4195835 / 3145727`) produces wrong precision when `PENTIUM_FDIV_BUG=1`. |
| `APPJ-3` `[Roadmap+Gap]` | `appJ_arithmetic/ieee754_fpu_fma_bf16` | 5th–7th Ed App J.3–J.7; 7th Ed Ch 7 | **IEEE-754 single-precision (`fp32`) Adder, Multiplier, and Fused Multiply-Add (FMA)** supporting all 4 rounding modes (RNE, RTZ, RUP, RDN) via **guard, round, sticky bits**, subnormals, $\pm 0$, $\pm \infty$, NaNs, and 5 exception flags (`NV, DZ, OF, UF, NX`), plus selectable **`bf16`/`fp8`-to-`fp32` FMA** mode showing single-rounding FMA precision vs. unfused `mul+add`. | Compare bit-for-bit (`32`-bit IEEE encoding + flags) against Python `struct`/`decimal`/exact-rational IEEE-754 golden model, including catastrophic-cancellation FMA cases and subnormal underflow. |

---

## 7. Documentation Synchronization Checklist (`docs/editions.md` & `docs/roadmap.md`)

When an agent updates companion documentation alongside or prior to code changes, update these specific items:

1. **[`docs/editions.md`](../docs/editions.md) updates**:
   - Add missing rows to Section 3 ("Where each topic lives in this repository"): `1st Ed Ch 5` (processor control), `Ch 3 §§3.10–3.12 / 3rd–4th Ed Ch 3` (ILP limits & multithreading), `App A` (Instruction Set Principles), `App E` (Embedded Systems), `App G` (Vector Processors in More Depth), `App I` (Large-Scale Multiprocessors), `App K` (Survey of ISAs), `App L` (Advanced Address Translation), and `App M` (Historical Perspectives).
   - Expand the **7th Edition (2025)** entry in Section 1 to document chiplets/yield economics, embodied carbon & 4M sustainability, Alloy Cache / NUCA, side channels & Spectre/Meltdown, TAGE, Power10 / Xeon Platinum, Meta WSC / Google Jupiter OCS / AWS Nitro + Graviton3, TPU v4, Hopper/Blackwell Tensor Cores (2:4 sparsity, Transformer Engine), Graphcore IPU, Samsung NPU, and MLPerf.
2. **[`docs/roadmap.md`](../docs/roadmap.md) updates**:
   - Add sections for currently untracked textbook units: **App A / App K** (ISA principles & compressed decoders), **App D** (I/O queueing, RAID-6/Chipkill, DMA), **App E** (DSP Q-MAC/circular/bit-reversed/zero-overhead loops), **App G** (vector bank conflicts/gather-scatter/strip-mining), **App I** (transient coherence states, MCS/tree locks), and **App L** (superpages/nested translation/PWC).
   - Update **Ch 1**, **Ch 2**, **Ch 3**, **Ch 4**, **Ch 5**, **Ch 6**, **Ch 7**, **App F**, and **App J** planned lists with the unscheduled items identified in Section 6 above.
3. **Pass-count & index sync**:
   - Never leave a new example unlisted in [`data/index.json`](../data/index.json), [`README.md`](../README.md), [`docs/editions.md`](../docs/editions.md), [`docs/roadmap.md`](../docs/roadmap.md), or [`CLAUDE.md`](../CLAUDE.md) (update `66/66 passed` whenever examples are added).

---

## 8. Review Caveats

- This review compares edition chapters, appendices, figures, and exercises against the companion repository's 33 indexed examples (`66/66` tests in [`CLAUDE.md`](../CLAUDE.md)), [`docs/editions.md`](../docs/editions.md), [`docs/roadmap.md`](../docs/roadmap.md), [`data/index.json`](../data/index.json), [`scripts/run_tests.py`](../scripts/run_tests.py), and [`scripts/render-index.mjs`](../scripts/render-index.mjs).
- Textbook prose, figures, and exercise solutions are never reproduced; all backlog items are original implementations teaching the underlying quantitative principles.
- HDL simulations (`make test`) were not run during this documentation-only review; [`node scripts/render-index.mjs --check`](../scripts/render-index.mjs) was verified clean.
