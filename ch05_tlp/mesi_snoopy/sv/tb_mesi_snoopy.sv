`timescale 1ns/1ps
module tb_mesi_snoopy;
  localparam int P = 4;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic op_valid = 0, op_write = 0;  logic [1:0] op_core = 0;  logic [31:0] op_wdata = 0;
  logic [31:0] rdata, mem_out;  logic [1:0] bus_txn;  logic writeback;  logic [2*P-1:0] state_out;

  mesi_snoopy #(.P(P)) dut (.*);

  localparam [1:0] I = 0, S = 1, E = 2, M = 3;
  localparam [1:0] NONE = 0, BUSRD = 1, BUSRDX = 2, BUSUPGR = 3;
  int errors = 0;
  logic [31:0] golden;                         // last value written to the line (sequential consistency)

  function automatic [2*P-1:0] states(input [1:0] a, b, c, d); states = {d, c, b, a}; endfunction

  // perform one operation; check bus transaction, write-back flag and resulting states
  task automatic op(input [1:0] core, input bit wr, input [31:0] wdata, input [1:0] exp_txn, input bit exp_wb,
                    input [2*P-1:0] exp_states, input string what);
    @(negedge clk);
    op_valid = 1; op_core = core; op_write = wr; op_wdata = wdata;
    #1;
    if (bus_txn !== exp_txn || writeback !== exp_wb) begin
      errors++; $display("FAIL [%s] bus_txn=%0d wb=%b, expected %0d / %b", what, bus_txn, writeback, exp_txn, exp_wb);
    end
    if (!wr && rdata !== golden) begin errors++; $display("FAIL [%s] read %h expected %h", what, rdata, golden); end
    if (wr) golden = wdata;
    @(negedge clk);
    op_valid = 0;
    if (state_out !== exp_states) begin
      errors++; $display("FAIL [%s] states %b expected %b", what, state_out, exp_states);
    end
  endtask

  // coherence invariants, checked after every operation of the random phase
  task automatic check_invariants();
    int owners = 0, valids = 0;
    for (int j = 0; j < P; j++) begin
      if (state_out[2*j +: 2] == M || state_out[2*j +: 2] == E) owners++;
      if (state_out[2*j +: 2] != I) valids++;
    end
    if (owners > 1 || (owners == 1 && valids > 1)) begin errors++; $display("FAIL invariant: states %b", state_out); end
    for (int j = 0; j < P; j++)   // clean copies match memory
      if ((state_out[2*j +: 2] == S || state_out[2*j +: 2] == E) && mem_out !== golden) begin
        errors++; $display("FAIL invariant: clean copy but memory %h != golden %h", mem_out, golden);
      end
  endtask

  logic [31:0] seed = 32'd5150;
  initial begin
    golden = 0;
    repeat (2) @(negedge clk); rst_n = 1;
    //                core wr  data        txn      wb   states(c0,c1,c2,c3)
    op(0, 0, 0,          BUSRD,   0, states(E,I,I,I), "C0 read: first reader gets Exclusive");
    op(0, 1, 32'h99990000, NONE,    0, states(M,I,I,I), "C0 write in Exclusive: silent E->M, no bus traffic");
    op(1, 0, 0,          BUSRD,   1, states(S,S,I,I), "C1 read: C0 flushes dirty line, both Shared");
    op(1, 1, 32'hAAAA0001, BUSUPGR, 0, states(I,M,I,I), "C1 write to Shared: BusUpgr invalidates C0");
    op(1, 1, 32'hAAAA0002, NONE,    0, states(I,M,I,I), "C1 write hit in Modified: silent");
    op(2, 0, 0,          BUSRD,   1, states(I,S,S,I), "C2 read: C1 flushes dirty line, M->S");
    if (mem_out !== 32'hAAAA0002) begin errors++; $display("FAIL memory not updated by flush: %h", mem_out); end
    op(3, 1, 32'hBBBB0003, BUSRDX,  0, states(I,I,I,M), "C3 write miss: BusRdX invalidates sharers");
    op(3, 1, 32'hBBBB0004, NONE,    0, states(I,I,I,M), "C3 write hit in Modified: silent");
    op(0, 1, 32'hCCCC0005, BUSRDX,  1, states(M,I,I,I), "C0 write miss: C3 flushes then invalidates");
    op(0, 0, 0,          NONE,    0, states(M,I,I,I), "C0 read hit");
    op(2, 0, 0,          BUSRD,   1, states(S,I,S,I), "C2 read: C0 flushes, M->S");
    op(2, 1, 32'hDDDD0006, BUSUPGR, 0, states(I,I,M,I), "C2 write to Shared: BusUpgr");
    op(3, 0, 0,          BUSRD,   1, states(I,I,S,S), "C3 read: C2 flushes");
    op(2, 1, 32'hEEEE0007, BUSUPGR, 0, states(I,I,M,I), "C2 write: Upgr");

    // random phase: sequential consistency + invariants
    for (int i = 0; i < 3000; i++) begin
      logic [1:0] core; logic wr;
      seed = seed * 32'd1664525 + 32'd1013904223;
      core = seed[17:16];  wr = seed[24];
      @(negedge clk);
      op_valid = 1; op_core = core; op_write = wr; op_wdata = seed ^ 32'h5A5A5A5A;
      #1;
      if (!wr && rdata !== golden) begin errors++; $display("FAIL random read: %h expected %h", rdata, golden); end
      if (wr) golden = op_wdata;
      @(negedge clk);
      op_valid = 0;
      check_invariants();
    end
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
