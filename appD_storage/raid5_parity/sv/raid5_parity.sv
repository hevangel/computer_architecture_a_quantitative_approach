// RAID-5 parity arithmetic for one stripe (Appendix D).  Parity is the XOR of the data blocks,
// so XOR-ing *all* blocks of a healthy stripe gives zero, and the XOR of the survivors
// reconstructs a failed disk.  A small write need not read the whole stripe:
//     new_parity = old_parity ^ old_data ^ new_data
module raid5_parity #(
    parameter int DISKS = 5,         // total disks in the stripe (DISKS-1 data + 1 parity)
    parameter int W     = 32         // block width in bits (a "block" is one word here)
) (
    // parity generation
    input  logic [(DISKS-1)*W-1:0] data_blocks,
    output logic [W-1:0]           parity_out,
    // checking and reconstruction of a full stripe (data + parity blocks)
    input  logic [DISKS*W-1:0]     stripe,
    input  logic [$clog2(DISKS)-1:0] failed,
    output logic [W-1:0]           syndrome,          // 0 for a consistent stripe
    output logic [W-1:0]           rebuilt,           // contents of disk `failed`
    // small-write parity update
    input  logic [W-1:0]           old_data, new_data, old_parity,
    output logic [W-1:0]           new_parity
);
  always_comb begin
    parity_out = '0;
    for (int i = 0; i < DISKS-1; i++) parity_out ^= data_blocks[i*W +: W];
    syndrome = '0;
    rebuilt  = '0;
    for (int i = 0; i < DISKS; i++) begin
      syndrome ^= stripe[i*W +: W];
      if (i != int'(failed)) rebuilt ^= stripe[i*W +: W];
    end
    new_parity = old_parity ^ old_data ^ new_data;
  end
endmodule
