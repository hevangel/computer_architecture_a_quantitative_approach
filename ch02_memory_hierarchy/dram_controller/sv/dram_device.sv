// A behavioural DRAM device with an independent TIMING CHECKER (Chapter 2: DRAM organisation and timing).
//
// Geometry: 4 banks x 16 rows x 4 bursts per row; one burst = BL beats of 32 bits (128 bits here, moved by one RD/WR command).  The burst address used by the
// controller is {row[3:0], bank[1:0], col[1:0]}.  Each bank has a ROW BUFFER: ACT copies a row into it, RD/WR access the open row, PRE closes it.
//
// Commands (cmd_valid with cmd): 1 ACT(bank,row)  2 RD(bank,col)  3 WR(bank,col,wdata)  4 PRE(bank)  5 REF (all banks must be precharged).
// A RD at command cycle r returns its burst in the single cycle r + tCL + BL (rd_valid, rd_data): beats occupy r+tCL .. r+tCL+BL-1.  A WR stores its data at once
// (the write latency tCWL only matters for the timing constraints that follow it).
//
// The checker keeps a timestamp of every command and flags -- with a message and the sticky `violation` bit -- anything that breaks a constraint or the protocol:
//   ACT: bank idle;  >= tRP after PRE of that bank;  >= tRFC after REF;  >= tRRD after any ACT
//   RD/WR: bank active;  >= tRCD after ACT;  >= tCCD after any column command;  RD >= tWTR after write data;  WR >= tRTW after a RD
//   PRE: bank active;  >= tRAS after ACT;  >= tRTP after RD;  >= tWR after write data
//   REF: all banks idle and >= tRP after their PRE.   It also records the longest gap between refreshes.
module dram_device #(
    parameter int BL   = 4,
    parameter int tRCD = 3, parameter int tCL = 3, parameter int tCWL = 2, parameter int tRP = 3, parameter int tRAS = 7,
    parameter int tWR = 3, parameter int tRTP = 2, parameter int tRRD = 2, parameter int tCCD = 4, parameter int tWTR = 3,
    parameter int tRTW = 6, parameter int tRFC = 12
) (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         cmd_valid,
    input  logic [2:0]   cmd,
    input  logic [1:0]   cmd_bank,
    input  logic [3:0]   cmd_row,
    input  logic [1:0]   cmd_col,
    input  logic [127:0] cmd_wdata,
    output logic         rd_valid,
    output logic [127:0] rd_data,
    output logic         violation,         // sticky
    output logic [31:0]  stat_refs,
    output logic [31:0]  max_ref_gap       // longest interval between two REF commands (cycles)
);
  localparam int NEVER = -1000000;
  logic [127:0] mem [0:255];
  logic         active [0:3];
  logic [3:0]   orow   [0:3];
  int last_act [0:3], last_pre [0:3], last_rd_b [0:3], last_wr_end_b [0:3];
  int last_act_any, last_col_any, last_ref, last_rd_any, last_wr_end_any;
  int now;
  logic [7:0]   rd_cnt [0:3];
  logic [127:0] rd_dat [0:3];

  function automatic logic [127:0] init_burst(input int a);          // initial memory contents: word k of burst a
    for (int k = 0; k < 4; k++) init_burst[32*k +: 32] = 32'hD0000000 | (a << 8) | k;
  endfunction

  assign rd_valid = (rd_cnt[0] == 8'd1) || (rd_cnt[1] == 8'd1) || (rd_cnt[2] == 8'd1) || (rd_cnt[3] == 8'd1);
  always_comb begin
    rd_data = '0;
    for (int s = 0; s < 4; s++) if (rd_cnt[s] == 8'd1) rd_data = rd_dat[s];
  end

  task automatic fail(input string what);
    violation <= 1'b1;
    $display("DRAM VIOLATION at cycle %0d: %s", now, what);
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      violation <= 1'b0; stat_refs <= '0; max_ref_gap <= '0; now <= 0;
      last_act_any <= NEVER; last_col_any <= NEVER; last_ref <= NEVER; last_rd_any <= NEVER; last_wr_end_any <= NEVER;
      for (int b = 0; b < 4; b++) begin active[b] <= 1'b0; orow[b] <= '0; last_act[b] <= NEVER; last_pre[b] <= NEVER; last_rd_b[b] <= NEVER; last_wr_end_b[b] <= NEVER; rd_cnt[b] <= '0; rd_dat[b] <= '0; end
      for (int a = 0; a < 256; a++) mem[a] <= init_burst(a);
    end else begin
      now <= now + 1;
      for (int s = 0; s < 4; s++) if (rd_cnt[s] != 8'd0) rd_cnt[s] <= rd_cnt[s] - 8'd1;
      if (cmd_valid) begin
        case (cmd)
          3'd1: begin                                                                      // ACT
            if (active[cmd_bank])                         fail("ACT to a bank with an open row");
            if (now - last_pre[cmd_bank] < tRP)           fail("ACT before tRP after PRE");
            if (now - last_ref < tRFC)                    fail("ACT before tRFC after REF");
            if (now - last_act_any < tRRD)                fail("ACT before tRRD after another ACT");
            active[cmd_bank] <= 1'b1;  orow[cmd_bank] <= cmd_row;  last_act[cmd_bank] <= now;  last_act_any <= now;
          end
          3'd2, 3'd3: begin                                                                // RD / WR
            if (!active[cmd_bank])                        fail("column command to a closed bank");
            if (now - last_act[cmd_bank] < tRCD)          fail("column command before tRCD after ACT");
            if (now - last_col_any < tCCD)                fail("column commands closer than tCCD");
            if (cmd == 3'd2 && now - last_wr_end_any < tWTR) fail("RD before tWTR after write data");
            if (cmd == 3'd3 && now - last_rd_any < tRTW)  fail("WR before tRTW after a RD");
            last_col_any <= now;
            if (cmd == 3'd2) begin
              last_rd_b[cmd_bank] <= now;  last_rd_any <= now;
              begin : alloc                                                              // take a slot that is free or finishing this cycle
                int taken;  taken = 0;
                for (int s = 0; s < 4; s++) if (taken == 0 && (rd_cnt[s] == 8'd0 || rd_cnt[s] == 8'd1)) begin
                  rd_cnt[s] <= 8'(tCL + BL);  rd_dat[s] <= mem[{orow[cmd_bank], cmd_bank, cmd_col}];  taken = 1;
                end
              end
            end else begin
              mem[{orow[cmd_bank], cmd_bank, cmd_col}] <= cmd_wdata;
              last_wr_end_b[cmd_bank] <= now + tCWL + BL;  last_wr_end_any <= now + tCWL + BL;
            end
          end
          3'd4: begin                                                                      // PRE
            if (!active[cmd_bank])                        fail("PRE to a closed bank");
            if (now - last_act[cmd_bank] < tRAS)          fail("PRE before tRAS after ACT");
            if (now - last_rd_b[cmd_bank] < tRTP)         fail("PRE before tRTP after RD");
            if (now - last_wr_end_b[cmd_bank] < tWR)      fail("PRE before tWR after write data");
            active[cmd_bank] <= 1'b0;  last_pre[cmd_bank] <= now;
          end
          3'd5: begin                                                                      // REF
            for (int b = 0; b < 4; b++) begin
              if (active[b])                              fail("REF with an open bank");
              if (now - last_pre[b] < tRP)                fail("REF before tRP after PRE");
            end
            if (now - last_ref < tRFC)                    fail("REF before tRFC after the previous REF");
            if (last_ref != NEVER && now - last_ref > int'(max_ref_gap)) max_ref_gap <= 32'(now - last_ref);
            last_ref <= now;  stat_refs <= stat_refs + 1;
          end
          default: ;
        endcase
      end
    end
  end
endmodule
