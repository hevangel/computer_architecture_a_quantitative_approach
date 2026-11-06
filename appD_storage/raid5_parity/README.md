# RAID-5 Parity

**Topic:** Appendix D (Storage Systems) · **Editions:** disks and RAID are a main chapter through the 4th edition,
supplemental material afterwards ·
**Files:** [`sv/raid5_parity.sv`](sv/raid5_parity.sv), [`vhdl/raid5_parity.vhd`](vhdl/raid5_parity.vhd)

## Background

**RAID** (Redundant Array of Independent Disks) combines disks for capacity, performance and dependability.
RAID 5 stripes data across `DISKS - 1` disks and stores one **parity** block per stripe (rotating over the
disks so no single disk is a bottleneck). Parity is the bitwise XOR of the data blocks:

```
P = D0 ^ D1 ^ ... ^ D(n-1)
```

Because XOR is its own inverse, the array tolerates the loss of any one disk:

* **Check:** XOR of *all* blocks (data and parity) of a healthy stripe is **zero** -- the syndrome.
* **Rebuild:** the contents of the failed disk are the XOR of all the *surviving* blocks.
* **Small write:** updating one data block does not require reading the whole stripe (the "small-write
  problem" is that it still costs 2 reads + 2 writes):

  ```
  new_parity = old_parity ^ old_data ^ new_data
  ```

Availability follows from the reconstruction time: the array is lost only if a second disk fails before the
first is rebuilt (the MTTF analysis in the appendix).

## Design

A combinational module with generics `DISKS` (default 5: 4 data + 1 parity) and `W` (block width, 32). It has
three independent function blocks: parity generation from the data blocks; syndrome and rebuild of a failed disk
`failed` for a full stripe; and the small-write parity update.

## Verification

For 200 random stripes the testbench generates parity, verifies the syndrome is zero, then for **every** disk
index checks that `rebuilt` equals the original block. It then rewrites data disk 2 and checks that the
small-write formula equals the parity recomputed from scratch.

## Run it

```bash
make test T=raid5_parity
```

## Exercises

1. Add **RAID 6** with a second, Reed-Solomon (P+Q) parity so two failures can be survived.
2. Model rotating parity placement and show a controller that maps (stripe, disk) to parity/data roles.
3. Combine with [`hamming_secded`](../hamming_secded) to protect the parity computation itself.
