`timescale 1ns/1ps
// PROG 0 (divergent):  y[tid] = (x[tid] even) ? 3*x[tid] : x[tid] + 100,   with x[tid] = tid
//    TID LD ANDI SSY BEQZ | ADDI BRA SYNC | ADDI MUL SYNC | ST EXIT   = 13 warp-instructions per warp, 80 lane-ops (8 lanes, half masked on 6 of them)
// PROG 1 (uniform branches): one BEQZ every lane takes and one that no lane takes; y[tid] = tid + 7.   7 warp-instructions, 56 lane-ops per warp
// Expected cycle / idle counts come from an independent Python model of the round-robin scheduler (LD_LAT = 6):
//    PROG 0:  1 warp -> 18 cycles, 5 idle      4 warps -> 54 cycles, 2 idle  (vs 72 if the four warps ran one after another)
//    PROG 1:  1 warp ->  7 cycles, 0 idle      4 warps -> 28 cycles, 0 idle
module simt_harness #(parameter int NW = 4, parameter int PROG = 0) (input logic clk, input logic rst_n, output logic done, output integer errors);
  localparam int WS = 8;
  logic [7:0] imem_addr;  logic [31:0] imem_rdata;
  logic [WS*16-1:0] dmem_addr;  logic [WS*32-1:0] dmem_wdata, dmem_rdata;  logic [WS-1:0] dmem_we;
  logic all_done;  logic [31:0] cycles, issued, lane_ops, idle;

  simt_core #(.NW(NW), .WS(WS), .LD_LAT(6)) dut (.clk, .rst_n, .imem_addr, .imem_rdata, .dmem_addr, .dmem_wdata, .dmem_we, .dmem_rdata,
                                                  .all_done, .stat_cycles(cycles), .stat_issued(issued), .stat_lane_ops(lane_ops), .stat_idle(idle));

  function automatic [31:0] ins(input [4:0] o, input [3:0] rd, ra, rb, input int imm); ins = {o, rd, ra, rb, imm[14:0]}; endfunction
  localparam [4:0] OP_ADD=1, OP_MUL=3, OP_ANDI=5, OP_ADDI=6, OP_TID=7, OP_LD=8, OP_ST=9, OP_BEQZ=10, OP_BRA=11, OP_SSY=12, OP_SYNC=13, OP_EXIT=14;

  logic [31:0] imem [0:31];
  logic [31:0] dmem [0:127];
  assign imem_rdata = imem[imem_addr[4:0]];
  always_comb for (int l = 0; l < WS; l++) dmem_rdata[32*l +: 32] = dmem[dmem_addr[16*l +: 7]];
  always_ff @(posedge clk) for (int l = 0; l < WS; l++) if (dmem_we[l]) dmem[dmem_addr[16*l +: 7]] <= dmem_wdata[32*l +: 32];

  initial begin
    for (int i = 0; i < 32; i++) imem[i] = 0;
    for (int i = 0; i < 128; i++) dmem[i] = 0;
    for (int t = 0; t < 32; t++) dmem[t] = t;                          // x[tid] = tid at words 0..31, y at words 64..95
    if (PROG == 0) begin
      imem[0]  = ins(OP_TID,  1, 0, 0, 0);
      imem[1]  = ins(OP_LD,   2, 1, 0, 0);          // r2 = x[tid]
      imem[2]  = ins(OP_ANDI, 3, 2, 0, 1);          // r3 = r2 & 1
      imem[3]  = ins(OP_SSY,  0, 0, 0, 0);
      imem[4]  = ins(OP_BEQZ, 0, 3, 0, 7);          // even lanes (r3 == 0) go to 7, odd lanes fall through
      imem[5]  = ins(OP_ADDI, 4, 2, 0, 100);        // odd path:  y = x + 100
      imem[6]  = ins(OP_BRA,  0, 0, 0, 9);
      imem[7]  = ins(OP_ADDI, 5, 0, 0, 3);          // even path: y = 3 * x
      imem[8]  = ins(OP_MUL,  4, 2, 5, 0);
      imem[9]  = ins(OP_SYNC, 0, 0, 0, 0);          // reconvergence point
      imem[10] = ins(OP_ST,   0, 1, 4, 64);         // y[tid] = r4
      imem[11] = ins(OP_EXIT, 0, 0, 0, 0);
    end else begin
      imem[0]  = ins(OP_TID,  1, 0, 0, 0);
      imem[1]  = ins(OP_BEQZ, 0, 6, 0, 4);          // r6 == 0 in every lane: uniform jump to 4
      imem[2]  = ins(OP_ADDI, 1, 1, 0, 1000);       // skipped
      imem[3]  = ins(OP_ADDI, 1, 1, 0, 1000);       // skipped
      imem[4]  = ins(OP_ADDI, 7, 0, 0, 1);          // r7 = 1 in every lane
      imem[5]  = ins(OP_BEQZ, 0, 7, 0, 8);          // r7 != 0 in every lane: uniform fall-through
      imem[6]  = ins(OP_ADDI, 2, 1, 0, 7);
      imem[7]  = ins(OP_ST,   0, 1, 2, 64);         // y[tid] = tid + 7
      imem[8]  = ins(OP_EXIT, 0, 0, 0, 0);
    end
  end

  integer e;
  task automatic check_stat(input string name, input [31:0] got, input int expect_v);
    if (got !== expect_v) begin e++; $display("FAIL [NW=%0d PROG=%0d] %s = %0d, expected %0d", NW, PROG, name, got, expect_v); end
  endtask

  initial begin
    int t, exp_y, exp_cycles, exp_idle, exp_issued, exp_ops;
    e = 0; done = 0; errors = 0;
    @(posedge rst_n);
    t = 0;
    while (!all_done && t < 1000) begin @(posedge clk); t++; end
    if (!all_done) begin e++; $display("FAIL [NW=%0d PROG=%0d] never finished", NW, PROG); end
    @(negedge clk);
    for (int tid = 0; tid < NW * WS; tid++) begin
      if (PROG == 0) exp_y = (tid % 2 == 0) ? 3 * tid : tid + 100; else exp_y = tid + 7;
      if (dmem[64 + tid] !== exp_y) begin e++; $display("FAIL [NW=%0d PROG=%0d] y[%0d] = %0d, expected %0d", NW, PROG, tid, dmem[64 + tid], exp_y); end
    end
    if (PROG == 0) begin
      exp_cycles = (NW == 1) ? 18 : 54;  exp_idle = (NW == 1) ? 5 : 2;  exp_issued = 13 * NW;  exp_ops = 80 * NW;
    end else begin
      exp_cycles = 7 * NW;  exp_idle = 0;  exp_issued = 7 * NW;  exp_ops = 56 * NW;
    end
    check_stat("cycles", cycles, exp_cycles);  check_stat("idle cycles", idle, exp_idle);
    check_stat("warp-instructions", issued, exp_issued);  check_stat("lane-ops", lane_ops, exp_ops);
    $display("NW=%0d PROG=%0d: %0d cycles (%0d idle), %0d warp-instr, SIMT efficiency = %f", NW, PROG, cycles, idle, issued, lane_ops * 1.0 / (issued * WS));
    errors = e;  done = 1;
  end
endmodule

module async_harness(input logic clk,rst_n, output logic done);
  logic [7:0] ia,warp,resp_warp=0; logic [2:0] req_rd,resp_rd=0; logic [31:0] instr,addr,wdata,rdata=42;
  logic [0:0] we,mask; logic req,ready=1,wr,resp=0,all_done;
  logic [31:0] cycles,issued,ops,idle;
  function automatic [31:0] ins(input [4:0] op,input [3:0] rd,ra,rb,input integer imm);
    ins={op,rd,ra,rb,imm[14:0]};
  endfunction
  always_comb begin
    case(ia)
      0:instr=ins(8,2,0,0,0);   // first load
      1:instr=ins(8,5,0,0,0);   // second load while first pending
      2:instr=ins(8,7,0,0,0);   // third load
      3:instr=ins(6,3,0,0,11);  // independent
      4:instr=ins(6,2,0,0,99);  // WAW waits for r2
      5:instr=ins(1,4,2,3,0);
      6:instr=ins(1,6,4,7,0);   // second-source RAW waits for r7
      7:instr=ins(1,6,6,5,0);   // consume out-of-order r5 result
      8:instr=ins(9,0,0,6,0);
      default:instr=ins(14,0,0,0,0);
    endcase
  end
  simt_core #(.NW(1),.WS(1),.ASYNC_MEM(1)) dut(.clk,.rst_n,.imem_addr(ia),.imem_rdata(instr),
    .dmem_addr(addr[15:0]),.dmem_wdata(wdata),.dmem_we(we),.dmem_rdata(32'b0),.all_done,
    .stat_cycles(cycles),.stat_issued(issued),.stat_lane_ops(ops),.stat_idle(idle),
    .mem_req_valid(req),.mem_req_ready(ready),.mem_req_write(wr),.mem_req_warp(warp),.mem_req_rd(req_rd),.mem_req_mask(mask),
    .mem_resp_valid(resp),.mem_resp_warp(resp_warp),.mem_resp_rd(resp_rd),.mem_resp_rdata(rdata));
  task automatic respond(input [2:0] reg_tag);
    begin @(negedge clk); resp_rd=reg_tag; rdata=(reg_tag==5)?9:42; resp=1; @(negedge clk); resp=0; end
  endtask
  initial begin #20000; if (!done) $fatal(1,"async test timeout"); end
  initial begin
    done=0; @(posedge rst_n);
    wait(req && req_rd==7); // r5 returns on the same edge that r7 is accepted
    respond(5); repeat(10) @(negedge clk);
    if(issued!=4 || all_done) $fatal(1,"overlapping loads or WAW stall");
    respond(2); repeat(10) @(negedge clk);
    if(issued!=6 || all_done) $fatal(1,"RAW stall after simultaneous response/request");
    respond(7);
    wait(req && wr); #1; if(wdata!==32'd161) $fatal(1,"RAW/WAW result");
    @(negedge clk); repeat(4) @(negedge clk);
    if(all_done) $fatal(1,"exit before store response");
    respond(0);
    wait(all_done); @(negedge clk); if(issued!=10) $fatal(1,"async issue count");
    done=1;
  end
endmodule

module tb_simt_core;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic [3:0] d; logic async_done; integer er [0:3];
  async_harness ha (.clk,.rst_n,.done(async_done));
  simt_harness #(.NW(1), .PROG(0)) h0 (.clk, .rst_n, .done(d[0]), .errors(er[0]));
  simt_harness #(.NW(4), .PROG(0)) h1 (.clk, .rst_n, .done(d[1]), .errors(er[1]));
  simt_harness #(.NW(1), .PROG(1)) h2 (.clk, .rst_n, .done(d[2]), .errors(er[2]));
  simt_harness #(.NW(4), .PROG(1)) h3 (.clk, .rst_n, .done(d[3]), .errors(er[3]));
  initial begin
    repeat (2) @(negedge clk); rst_n = 1;
    wait (d == 4'hF && async_done);
    #1;
    if (er[0] + er[1] + er[2] + er[3] == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", er[0] + er[1] + er[2] + er[3]);
    $finish;
  end
endmodule
