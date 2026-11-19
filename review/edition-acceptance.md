# Edition coverage acceptance plan

The [baseline review](edition-coverage.md#6-concrete-work-item-backlog--module-specifications-agent-execution-queue) defines the numbered scope and edition references. This companion records the implementation evidence available at checkpoint `41776ad` and the checks needed to accept each item. The checkpoint had 29 paired HDL targets, five Python targets, one SystemVerilog prototype and 12 targets without a module. The current tree has an implementation at every numbered path, with 42 paired HDL targets and five Python targets. A target's presence or a passing repository regression alone does not establish that it meets its review row.

For paired examples, run `python scripts/run_tests.py -v <target>` with Icarus and GHDL. Use the same stimulus and compare architectural results, counters and cycle boundaries in both languages. Obtain expected values from an independent model, hand calculation or a validated reference. Run each Python suite with `unittest` discovery from its own directory to avoid importing an unrelated module with the same name. Keep tool versions, command output, vector provenance and any scope exclusions with the item evidence.

| Item | Checkpoint artifact and acceptance work |
| --- | --- |
| CH01-1 | Paired counters. Replay baseline and reduced-toggle traces against independent energy and cycle arithmetic. Check the 30% threshold, Q16.16 units and zero-retirement behavior. |
| CH01-2 | Python suite. Reconcile the source-specific dual-supply reliability example with the edition text and independently bracket the chiplet cost crossover. |
| CH02-1 | Paired stream buffer. Compare identical sequential and interleaved traces with prefetch disabled and enabled. Check FIFO refill, stream replacement, the 70% sequential miss target and cycle parity. |
| CH02-2 | Paired two-way cache and cycle oracle. Reconcile primary and secondary misses, four concurrent MSHRs, hit-under-miss and forwarding from an outstanding write-back. |
| CH02-3 | Paired policy evaluator with a finite address model. Check all supported associativities and policies against identical traces, including exact 3C totals and the conflict reduction. |
| CH02-4 | Paired VIPT model with safe page-offset indexing. Check both way latencies, energy accounting, requested-word delivery before refill completion and alias safety. Record the supported indexing geometry. |
| CH02-5 | Paired DRAM-cache model with an illustrative predictor. Verify MAP-I against the edition reference before claiming fidelity. Compare serial, correctly predicted and incorrectly predicted service costs on the stated mix. |
| CH02-6 | Paired abstract cache model. Verify partition ownership and measure cross-domain eviction counters before and after isolation. |
| CH02-7 | Paired serialized nested walker. Count guest and host PTE reads, then repeat with the walk cache, cross-4-KiB superpage hits and alternating ASIDs. Distinguish the bounded TLB and serialized model from broader Appendix L coverage. |
| CH03-1 | Paired tournament predictor, BTB and RAS. Compare all three predictor choices on the same trace and check the direction and return-target metrics separately. |
| CH03-2 | Paired tagged-history predictor and Python reference. Compare cycle-level state and errors with the oracle, and compare long-history aliases with gshare under documented table sizes. |
| CH03-3 | Paired RV32I subset. Use the same unrolled dot product and scalar baseline, checking register and memory parity against the five-stage pipeline plus the requested IPC threshold. |
| CH03-4 | Paired speculative load replay engine. Check the independent-load cycle savings and the alias recovery trace. Establish which younger instructions actually replay and whether branch redirection occurs at resolution or broadcast. |
| CH03-5 | Paired external-issue PRF engine. Verify WAW/WAR state, free-register conservation and precise restoration of the speculative map under an older commit and nested branch flush. |
| CH03-6 | Paired preloaded two-thread core. Compare per-thread outputs and shared issue limits across all modes. Keep the specified IPC ordering tied to the qualifying workload. |
| CH03-7 | Paired abstract timing model. Qualify through equal committed results and suppression of transient cache fills by the mitigation in the model. |
| APPH-1 | Paired VLIW cores with predication, rotating banks, NaT and ALAT. Both compare 29 bundles against the original 31-bundle pipelined-workload baseline, and verify deferred fault and explicit recovery behavior. |
| CH04-1 | Paired pack and shuffle unit. Check transpose and quantization against independently generated expected bytes, including signed extrema and lane order. |
| CH04-2 | Paired coalesced SIMT wrapper. Check transaction counts by lane width, replay factors, register dependencies and barrier release only after participating warps finish their outstanding memory operations. |
| CH04-3 | Paired banked vector memory with a 64-element command limit. Verify stride, bank counters, gather/scatter and 16+16+13 strip mining. Establish arbitrary-length command support and derive the throughput metrics separately. |
| CH04-4 | Python roofline and bounded affine models. Trace each numerical case to its edition and exercise independent witnesses for loop-carried dependence, including boundary and no-solution cases. |
| CH05-1 | Paired explicit-drain consistency model. Enumerate legal operation schedules for SB and MP and verify which outcomes are reachable under SC, TSO and fences. |
| CH05-2 | Paired reservation and back-off model. Exercise invalidation, compare TAS/TTAS/back-off under identical contenders and check two barrier phases with deliberately staggered arrivals. |
| CH05-3 | Paired serialized directory. Check dirty and clean replacement, data-source ownership and measured messages for all three sharer encodings on the same trace. |
| CH05-4 | Paired atomic four-core MOESI models. Both testbenches verify Owned forwarding without write-back, dirty replacement, 3C and true-sharing categories, and ten adjacent-word false misses versus zero with padding. |
| CH05-5 | Paired single-line split-transaction MSI. Both testbenches cover simultaneous upgrades, backpressured data, losing-sharer retry, dirty eviction and final load data. Concurrent ordering across different lines remains outside this model. |
| CH05-6 | Paired MCS and combining-tree models. The tests cover delayed successor publication, exclusive FIFO handoff, 2/4/8-node message counts and two barrier phases. Root traffic is constant and tree depth logarithmic while total messages remain linear. |
| CH06-1 | Python warehouse-scale suite. Independently check PUE and TCO against edition-specific inputs and validate tail latency against uniform and heavy-tailed service traces with equal offered traffic. |
| CH06-2 | Paired Clos/OCS fabric. Both testbenches verify loss-free fixed, hot-pair reconfigured and distributed workloads. The same hot-pair workload takes 130 versus 66 cycles. A blocked packet delays configuration commit until drain. |
| CH07-1 | Paired convolution. Compare all valid outputs to an independent 16×16 image convolution and verify initiation rate separately from boundary bubbles. |
| CH07-2 | Paired output-stationary array and postprocessor. Check signed matrix results, bias order, activation, shifts and saturation against fixed-point golden values. |
| CH07-3 | Paired BF16/FP8 dense and 2:4 sparse tiles. Thirty cases match exact Python results and use four versus two compute cycles and 16 versus eight weight words. The guide documents zero-product and memory interface assumptions. |
| CH07-4 | Paired bounded halo model. Compare clamp/wrap and exact Sobel results over an 8×8 tile and count off-chip fetches independently of scratchpad accesses. |
| APPA-1 | Paired compressed subset and mixed-width fetch. Verify the documented encoding set, rejected/reserved encodings and static and dynamic loop byte reductions under the same program semantics. |
| APPA-2 | Python ISA traffic model. Check common results and exact instruction and byte ratios for the cited four-class sequence as well as the synthetic expression and sort. |
| APPC-1 | Paired hardwired FSM and ROM sequencer. The original test image yields identical full state and 49 retirements. Hardwired and microcoded traces agree cycle for cycle at 197 cycles, versus 78 for the five-stage core. |
| APPC-2 | Paired five-stage variants. Both verify MEM priority over concurrent ECALL, suppression of a faulting store, preservation of older state, isolated traps, and MEPC/MCAUSE handler state and MRET resume. Full privilege semantics remain outside the model. |
| APPC-3 | Paired eight-stage models. A matched MIPS64 trace verifies two load bubbles, a three-cycle taken transfer, equivalent no-delay state and an optional delay slot. Cache tags and optional pipelined FP remain outside the model. |
| APPD-1 | Paired RAID-6 and symbol ECC. Exhaust disk-erasure combinations and chip nibble faults, comparing restored data and parity with the independent field model. |
| APPD-2 | Paired DMA and FIFO wrapper. Verify descriptor lengths, backpressure, completion IRQ and the contrast between stale and coherent CPU readback. |
| APPD-3 | Python queueing and rebuild models. Check cited worked examples, document the disk seek parameters and independently verify the MTTDL error bound. |
| APPE-1 | Paired DSP datapath. Exercise FIR repeat control, buffer wrap, positive and negative saturation and the 16-address FFT permutation against independent vectors. |
| APPF-1 | Paired 4×4 single-flit VC models. Both deliver 80 distinct hotspot packets with 240 minimal hops and a disabled east link, and show one-cycle speculative versus two-cycle serialized hop timing. Routes may reorder packets. |
| APPF-2 | Paired Omega and iSLIP models. Both tests verify wormhole order and transpose blocking, then measure 86 accepted matches in four rounds versus 76 in one on identical request snapshots. |
| APPJ-1 | Paired carry and multiplier examples. Check exhaustive products, carry-chain vectors and the documented distinction between logic-depth proxies and measured timing. |
| APPJ-2 | Paired carry-save radix-4 SRT divider. Both testbenches check 577 vectors against exact integer and mantissa expectations and exercise the omitted-cell precision failure. The separate mathematical model verifies the remainder bound and all five cell addresses. |
| APPJ-3 | Exact Python oracle and SystemVerilog prototype. Match the VHDL port against the shared vectors, including result bits and flags for each rounding mode. Verify input format and scale limits, exact cancellation and subnormal rounding. Register both testbenches only after parity. Both are now registered and accept the shared 7,156-vector file. |

## Design and acceptance notes

### APPH-1 · Software-pipelined VLIW

Define predication before issue side effects. A false predicate suppresses register writes, stores and deferred checks. Track NaT alongside register values and propagate it through dependent arithmetic. For advanced loads, record an address range with the destination tag and invalidate overlapping entries on stores or replacement. A failed check must take the documented recovery path. Use one scalar DAXPY oracle for the baseline and the prologue, steady-state kernel and epilogue. Check short loop counts and interrupted reuse of rotating registers as well as steady-state IPC. Include suppressed speculative faults, an executed check, overlapping and disjoint stores, and table replacement.

### CH05-4 · MOESI and sharing classification

Model at least two words per line. Track one dirty owner, sharers and the source of each response. A dirty peer read turns M into O and supplies the requested value with no memory write. Check dirty owner eviction and writes by both an owner and a sharer. Classify a miss once by using invalidation history and the touched word, with independent cold and fully associative shadow tracking for other misses. Apply fixed precedence and require the counters to sum to total misses. Compare adjacent and padded writer traces, then include a shared-word control to exercise true sharing.

### CH05-5 · Split-transaction coherence

Separate request acceptance, snoop ordering and data response. Attach an identity and line address to pending requests. Define transitions for IM_AD, IM_D, SM_AD and MI_A, including an incoming invalidation while an upgrade is pending. Arbitrate simultaneous upgrades deterministically, then let the loser retry against the updated ownership. Inject delayed data and backpressure, check at most one writable copy at every step, and compare final read values with a sequential replay in bus order. Bound the test drain time.

### CH05-6 · Queue lock and combining barrier

Give each MCS contender its own flag and successor field. Exercise uncontended unlock, delayed enqueue-link publication and FIFO handoff under contention. Compare remote traffic per handoff for 2, 4 and 8 contenders while keeping the counting boundary identical. Use a reusable tree barrier with upward arrival and downward release and compare it with a centralized counter. Measure critical-path depth and root hot-spot traffic separately from total messages. Run consecutive phases with different arrival orders.

### CH06-2 · Clos with optical circuit reconfiguration

Use eight leaves, four spines and a documented static 2:1 baseline. Represent each 2×2 switch as a circuit mapping with exclusivity and define when a new schedule takes effect relative to in-flight traffic. Assign every packet an identity. Exercise skewed pairs and a uniform control under identical seeds, offered loads, observation windows and backpressure rules. Match sent IDs to received IDs after drain, including packets present at reconfiguration. Measure delivered hot-pair throughput over the same steady-state interval and check the 1.5× threshold.

### CH07-3 · Sparse tensor arithmetic

Define 4×4 tile order, operand formats, scale application, and FP32 accumulator rounding. A 2:4 group must identify two distinct legal indices. Specify handling for illegal metadata and reconstruct implicit zeros for the dense reference. Compare sparse and dense results with the same mathematical operands and operation order, including signed values and cancellation. Count accepted weight reads and accumulation cycles separately, isolating setup and drain from the 2× steady-state target. Share the exact floating-point oracle with APPJ-3.

### APPC-1 · Hardwired and microcoded multicycle control

Use one architectural datapath, program image and memory map. Select either an explicit FSM or a micro-ROM with a micro-PC and opcode dispatch. Define each instruction's retirement edge and ensure stores occur once. Compare retirement and memory traces in both modes and against the existing five-stage reference. Report the same start and stop boundaries, retire count, measured CPI and the specified speedup on the shared workload.

### APPC-2 · Precise exceptions

Carry fault metadata and PC with each valid pipeline entry. Give the oldest pending fault priority, retire older operations, squash younger effects and record the winning cause and PC. Sample asynchronous requests at a defined architectural boundary. Test simultaneous older MEM and younger EX faults, then inspect handler entry, CSR contents, no younger writes and MRET resume. Add isolated IF, ID and asynchronous cases and a faulting store that never reaches memory.

### APPC-3 · Eight-stage superpipeline

Assign fetch, decode, execute, address translation/cache and register-write boundaries to the eight named stages. Enumerate bypass sources and bubble/flush behavior. Use identical encodings and initial state for the corresponding five-stage comparison. Measure two load-use delay cycles and three branch penalty cycles on isolated dependency traces, then test combined hazards and the delayed-branch option. Document optional FP scheduling and verify it independently before including it in the state comparison.

### APPF-1 · West-first routing and speculative allocation

Require all necessary westward movement before taking a different direction. Select among legal minimal outputs by downstream credit and define a deterministic tie break. Speculative switch grants may use the fast path only when VC allocation succeeds and credit is available. A canceled grant must neither consume credit nor move a flit. Exercise an unloaded router hop, a congested pair with two legal routes, and a bounded-drain hotspot stream with unique packet IDs, minimal-hop accounting and credit conservation checks. Adaptive paths can reorder packets.

### APPF-2 · Omega and iSLIP

Build three stages of 2×2 switches with explicit interstage wiring and credit return. Compare an independently derived stage path against each unblocked destination and a blocking permutation against the expected occupied links. Keep the iSLIP grant and accept pointers separate and update them according to the specified iteration rule. Compare accepted matches and sustained utilization with the stated round-robin baseline under identical request matrices. Keep Omega blocking and isolated crossbar utilization as separate measurements.

### APPJ-2 · Radix-4 SRT division

Specify normalization, the signed partial remainder recurrence, redundant digit selection from truncated remainder and divisor, and on-the-fly quotient conversion. Check the remainder range and two-bit digit cadence at each step and verify final quotient/remainder against integer or exact-rational arithmetic. Cover boundary table addresses and exceptional operands. Treat the five omitted selection entries as an explicit alternate table and require the cited positive operand pair to distinguish the two modes without changing unaffected control vectors.

## Verification scope

All numbered paths now have implementations. Use the checks above when expanding any bounded model or closing a remaining acceptance criterion. Run the integrated HDL suite and the standalone Python suites, and keep the generated index, roadmap and guides tied to verified behaviour.
