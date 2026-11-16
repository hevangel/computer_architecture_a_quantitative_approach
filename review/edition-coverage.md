# Edition coverage review

## Summary

The companion is a substantial, tested collection of runnable hardware examples, not a complete implementation of every subject in *Computer Architecture: A Quantitative Approach*. Its strongest coverage is processor microarchitecture, caches and translation, vector/SIMD/GPU fundamentals, cache coherence, selected interconnects, and integer arithmetic.

The largest remaining gaps are broader than individual RTL blocks: quantitative performance, power, cost, and dependability analysis; I/O and storage systems; warehouse-scale and cloud architecture; and embedded systems. The current roadmap already names some worthwhile additions, but it does not cover all of these areas.

This is a topic-coverage review, not a recommendation to reproduce the textbook chapters, prose, figures, or exercises. Any future additions should remain original and use the exact edition and section as a source when documenting technical claims.

## Sources and method

Compared the companion's [example index](../README.md), [edition map](../docs/editions.md), and [roadmap](../docs/roadmap.md) with the local Markdown editions:

- [First edition (1990)](../../textbooks/ComputerArchitecture/CA_1st_Ed_1990.md)
- [Second edition (1996)](../../textbooks/ComputerArchitecture/CA_2nd_Ed_1996.md)
- [Third edition (2002)](../../textbooks/ComputerArchitecture/CA_3rd_Ed_2002.md)
- [Fourth edition (2006)](../../textbooks/ComputerArchitecture/CA_4th_Ed_2006.md)
- [Fifth edition (2011)](../../textbooks/ComputerArchitecture/CA_5th_Ed_2011.md)
- [Sixth edition (2017)](../../textbooks/ComputerArchitecture/CA_6th_Ed_2017.md)
- [Seventh edition (2025)](../../textbooks/ComputerArchitecture/CA_7th_Ed_2025.md)

The edition transcriptions differ in OCR and heading quality. Topics below are based on their chapter and appendix structure and repeated topic descriptions, checked against the companion's indexed examples and roadmap. “Missing” means no dedicated example or model was found in those companion materials; it does not imply that every topic needs an RTL implementation.

## Findings

| Area | Existing coverage | What is still missing |
|---|---|---|
| Quantitative design, measurement, and dependability | Amdahl's Law is implemented. The roadmap proposes performance counters/CPI breakdown and a dynamic-power estimator. | A broader, worked treatment of benchmark selection and aggregation; cost and technology trends; static and system-level energy/power; and reliability, availability, and failure-rate tradeoffs. These are recurring foundations from the early editions through the latest editions, but currently have little beyond Amdahl's Law. |
| Instruction sets, compilers, and ILP | The companion has RV32I and DLX/MIPS64 pipeline examples, branch prediction, scoreboarding, Tomasulo/ROB, speculation, and a VLIW core. | The roadmap covers several useful pipeline and superscalar extensions, but there is no dedicated model of compiler scheduling, ISA design/encoding and workload use, or a systematic comparison of compiler-visible versus hardware ILP. ISA variants are not complete across all ISA-dependent examples. |
| Memory hierarchy and address translation | Set-associative and non-blocking caches, victim cache, prefetching, DRAM, TLB/page-table walking, and protection faults are represented. | Add broader memory-system tradeoff studies (including cache-policy/miss classification and memory technology) and virtual-memory/virtual-machine mechanisms. The TLB walker is useful but is not a model of a complete VM or hypervisor, and the 6th-edition advanced-address-translation material has no corresponding example. Some cache work is already on the roadmap. |
| I/O and storage systems | SECDED and RAID-5 parity illustrate error correction and redundancy. | There is no end-to-end I/O or storage-system model covering device/interface paths, storage performance and queueing, reliability/availability, or workload-level tradeoffs. The editions devote substantially more material to these topics than the current ECC and parity examples represent; this area is not called out as a distinct roadmap item. |
| Data-level parallelism | Vector lanes and chaining, packed SIMD operations, and a GPU-style SIMT core are implemented. | The roadmap proposes SIMD shuffle/pack operations and SIMT coalescing. Further gaps include vector masks and indirect/sparse access, compiler-driven loop/vector parallelism, and GPU memory-system behavior beyond the current core model. |
| Thread-level and large-scale parallelism | MESI snooping, directory MSI, and atomic spin locks are implemented. | Memory-consistency tests, LL/SC, barriers, and related coherence extensions are already planned. There is no broader model of distributed-memory/HPC applications, their communication costs, or their scaling behavior. |
| Warehouse-scale computers, request-level parallelism, and cloud | Chapter 6 has an introductory guide but no runnable model. A Python queueing/tail-latency/PUE model is planned. | That planned model is only a starting point: workload/programming models, cluster and service architecture, replication/failures, physical infrastructure, cost and energy, and virtualization/cloud tradeoffs remain unrepresented. This is a major gap in the 5th-7th editions. |
| Domain-specific architectures | One TPU-style systolic matrix-multiply unit is implemented. Convolution, activation/quantization, and an output-stationary variant are planned. | Beyond those planned variants, there is no comparative treatment of accelerator data movement, memory organization, energy/cost, or the different accelerator design approaches described in the 6th-7th editions. |
| Embedded systems | No example or model was found. | Embedded systems are covered in a dedicated appendix in later editions. Low-power and cost constraints, code/data size, real-time responsiveness, and embedded workload tradeoffs are not represented. This is not on the current roadmap. |
| Arithmetic | Carry-lookahead addition, Booth multiplication, and restoring division are implemented. IEEE-754 arithmetic and SRT division are planned. | Floating-point rounding, exceptional values, and fused operations are not yet represented; the existing arithmetic examples are integer-focused. |
| Interconnection networks and multiprocessor scale | Crossbar arbitration, mesh routing, virtual channels, and torus deadlock avoidance are implemented. | The basic network mechanisms are comparatively well represented. The remaining gap is their system-level application at larger scales, especially communication and scaling for scientific/HPC workloads, rather than another introductory router example. |

## Highest-value roadmap additions

1. Extend the Chapter 1 work into a small quantitative evaluation suite: benchmark aggregation, performance/energy/cost comparison, and dependability metrics. Keep the existing counter and power-estimator ideas as components of that larger goal.
2. Add a distinct storage/I/O model, with service time, queueing, throughput, and failure/redundancy tradeoffs. This fills a repeated gap not covered by the current Chapter 6 WSC plan.
3. Grow the planned WSC model beyond PUE and tail latency to include request/workload behavior, service-level availability, and the cost of the system that delivers the service.
4. Decide explicitly whether embedded systems and virtual-machine/address-translation topics are in scope. Both recur in the later editions but currently lack dedicated roadmap entries.
5. Continue the existing ILP, DLP, TLP, DSA, and arithmetic roadmap items, while documenting which edition/topic each example is intended to teach.

## Coverage caveats

- Edition chapter and appendix numbering changes substantially. Use the edition-specific headings in the source files rather than inferring a chapter number from a companion directory name.
- The source transcriptions have inconsistent OCR/heading structure, particularly in earlier editions. This review identifies broad topic gaps and does not claim a page-by-page audit of every exercise or figure.
- “Present” means an indexed implementation or guide was found; it does not certify that the implementation covers every variant, assumption, or case study in the textbook.
