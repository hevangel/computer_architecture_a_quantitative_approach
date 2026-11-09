# Directory-Based MSI Cache Coherence

**Topic:** Chapter 5 (distributed shared memory, directory protocols) · **Editions:** directories from the 2nd edition (the book's Figures use exactly these message types) ·
**Files:** [`sv/directory_msi.sv`](sv/directory_msi.sv), [`vhdl/directory_msi.vhd`](vhdl/directory_msi.vhd)

## Background

A snooping protocol ([`mesi_snoopy`](../mesi_snoopy)) needs a **broadcast medium**: every miss is seen by every cache, which does not scale beyond a handful of cores. A **directory** replaces the broadcast by
a table kept at each block's **home node**. For every block the directory records a state and the set of nodes that hold a copy (a **sharer bit vector**), so a miss talks only to the nodes that matter:

| Directory state | Meaning | Sharer vector |
|-----------------|---------|---------------|
| **U** uncached | memory has the only copy | empty |
| **S** shared | memory is up to date, read-only copies | the sharers |
| **M** modified | one node has the only, dirty copy | the single owner |

Caches have the states **I**, **S**, **M**. Nodes exchange point-to-point **messages**: the *request* (read miss / write miss) to the home, the *data reply*, *invalidates* with their *acknowledgements*, and *fetch* /
*fetch-invalidate* to the owner, who returns the data to the home. The home **serialises** requests to a block, which is what makes the protocol correct without a bus.

| Request | Directory | What happens | Messages | Hops |
|---------|-----------|--------------|---------:|-----:|
| read miss | U or S | data reply, sharer added | 2 | 2 |
| read miss | M | fetch to owner (it becomes S), data to home, reply | 4 | 4 |
| write miss / upgrade | U, or S with no other sharer | reply (requester becomes owner) | 2 | 2 |
| write | S with *k* other sharers | *k* invalidates in parallel, *k* acks, reply | 2*k* + 2 | 4 |
| write miss | M | fetch+invalidate to owner, data to home, reply | 4 | 4 |

## Design

`directory_msi` has `P` nodes, `NB` blocks, one home directory with the memory, and a parameter `LAT`, the cycles one message takes. A node or the home acts in the cycle a message arrives, so a request accepted in cycle *t*
**completes in cycle `t + hops*LAT + 1`** (two or four hops), and a **hit answers in cycle `t + 1`**. The home handles one transaction at a time, so the model applies the state changes when the transaction completes (nobody can
observe the intermediate states). Message counters per type (`request`, `reply`, `invalidate`, `ack`, `fetch`, `write-back to home`) and hit/miss counters are exposed; the directory, the sharer vectors and every cache can be read
through a debug port. Caches hold every block, so there are no replacements (see the exercises).

## Verification

**A hand-derived sequence on block 0** (4 nodes, memory `0xA0`; latency = `hops*LAT + 1`, `LAT` = 2 and 3 are both run):

| # | Operation | Directory | Caches C0..C3 | Hops | Messages |
|--:|-----------|-----------|---------------|-----:|---------:|
| 1 | C0 read | U -> S{0} | S - - - | 2 | 2 |
| 2 | C0 read | S{0} | S - - - | hit | 0 |
| 3 | C1 read | S{0,1} | S S - - | 2 | 2 |
| 4 | C2 read | S{0,1,2} | S S S - | 2 | 2 |
| 5 | C3 write `0xB1` | S{0,1,2} -> M{3} | - - - M | 4 | **8** (request, 3 invalidates, 3 acks, reply) |
| 6 | C3 write `0xB2` | M{3} | - - - M | hit | 0 |
| 7 | C0 read (gets `0xB2`) | M{3} -> S{0,3} | S - - S | 4 | 4 (request, fetch, data to home, reply) |
| 8 | C0 write `0xC3` | S{0,3} -> M{0} | M - - - | 4 | 4 (one invalidate, one ack) |
| 9 | C1 write `0xD4` | M{0} -> M{1} | - M - - | 4 | 4 |
| 10 | C1 read | M{1} | - M - - | hit | 0 |
| 11 | C2 write `0xE5` | M{1} -> M{2} | - - M - | 4 | 4 |
| 12 | C2 read block 1 | U -> S{2} | | 2 | 2 |
| 13 | C2 write block 1 | S{2} -> M{2} | | 2 | 2 (the only sharer upgrades: no invalidates) |
| 14 | C3 write block 2 | U -> M{3} | | 2 | 2 |

For every operation the testbench checks the latency, the number of messages (total and by type), the value read, and the full state (every cache, the directory state and sharer vector, memory) against a
**reference model** of the protocol written separately in the testbench; the hand-derived hop and message numbers above are asserted against that model as well.

**Random traffic** (3000 operations on 4 blocks, 35 % writes, plus 4000 operations on 16 nodes): every operation is compared with the reference model, reads return the last value written (sequential consistency per block),
and after every operation the invariants hold - at most one owner, no sharer alongside an owner, an uncached block is cached nowhere, the sharer bits equal the set of caches that hold the block, memory is clean unless the directory says M.

**Directory traffic against broadcast.** With 4 nodes all touching all blocks a miss costs **4.19 messages** on average (a snooping bus would reach 3 caches). With 16 nodes where each block is used by 3 of them, a miss costs
**4.13 messages** - about the same, while a broadcast would have to reach 15 caches per miss: the directory's traffic depends on the number of *sharers*, not on the number of nodes.

Mutation checks that fail the testbench in both languages: not invalidating the sharers, not downgrading the owner to Shared on a read, treating an upgrade by the only sharer as a four-hop transaction, miscounting the
acknowledgements. (Not writing the old owner's data back to memory on a write miss is *not* observable with one-word lines: the new owner overwrites it, and memory is refreshed the next time the line is downgraded.)
Both languages end at the same simulated time.

## Run it

```bash
make test T=directory_msi
```

## Exercises

1. Add **replacements**: a cache holding fewer lines than blocks must write back a dirty victim (a *data write-back* message) and tell the directory when it drops a clean copy (or let the sharer vector go stale and tolerate spurious invalidates).
2. Give blocks different **home nodes** (block *b* lives at node *b mod P*) and charge the latency by hop distance on a mesh such as [`mesh_router`](../../appF_interconnect/mesh_router).
3. Let the home handle **several blocks concurrently** and add a *busy/pending* directory state with NACKs or a request queue for the racing request.
4. Replace the full bit vector by a **limited-pointer** directory (e.g. four pointers, broadcast on overflow) and measure the extra invalidates on the sparse workload.
5. Add the **Exclusive** state of [`mesi_snoopy`](../mesi_snoopy): a read miss on an uncached block returns an exclusive copy that can be written without a directory transaction.
