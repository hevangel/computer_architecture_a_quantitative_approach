`timescale 1ns/1ps
// Three traces on a 4-set direct-mapped cache with 0 / 1 / 2 / 4 victim entries.  Lines 0, 4, 8 all map to set 0.
//   alt    : 0 4 0 4 ... (12 accesses)       two lines fight for one set
//   three  : 0 4 8 0 4 8 ... (12 accesses)   three lines fight for one set
//   random : 400 accesses over lines 0..11   (LCG)
// Expected (l1 hits, victim hits, misses) come from an independent Python model of LRU victim replacement:
//              V=0            V=1            V=2            V=4
//   alt      0/  0/ 12      0/ 10/  2      0/ 10/  2      0/ 10/  2
//   three    0/  0/ 12      0/  0/ 12      0/  9/  3      0/  9/  3
//   random 134/  0/266    134/ 32/234    134/ 75/191    134/141/125
// Cycle cost per access: L1 hit 1, victim hit 2, miss MEM_LAT + 3 (= 6 here) -> total cycles are checked against that formula.
module vc_harness #(parameter int VICT = 2) (input logic clk, input logic rst_n, output logic done, output integer errors, output integer misses_random);
  localparam int MEM_LAT = 3, LINE_WORDS = 4;
  logic local_rst = 0;
  wire  dut_rst_n = rst_n && !local_rst;
  logic req_valid = 0;  logic [15:0] req_addr = 0;
  logic resp_valid, mem_valid, mem_done = 0;  logic [31:0] resp_rdata;  logic [15:0] mem_addr;
  logic [LINE_WORDS*32-1:0] mem_rdata;
  logic [31:0] st_l1, st_vic, st_miss;

  victim_cache #(.SETS(4), .LINE_WORDS(LINE_WORDS), .VICT(VICT)) dut (.clk, .rst_n(dut_rst_n), .req_valid, .req_addr, .resp_valid, .resp_rdata,
      .mem_valid, .mem_addr, .mem_done, .mem_rdata, .stat_l1_hits(st_l1), .stat_victim_hits(st_vic), .stat_misses(st_miss));

  function automatic [31:0] word_val(input int w); word_val = 32'hC0DE0000 + w; endfunction
  int cnt = 0;
  always_ff @(posedge clk) begin
    mem_done <= 1'b0;
    if (mem_valid && !mem_done) begin
      if (cnt == MEM_LAT-1) begin
        cnt <= 0; mem_done <= 1'b1;
        for (int k = 0; k < LINE_WORDS; k++) mem_rdata[k*32 +: 32] <= word_val(int'(mem_addr) * LINE_WORDS + k);
      end else cnt <= cnt + 1;
    end else cnt <= 0;
  end

  integer e;  int total_cycles;
  task automatic access(input int line, input int off);
    int cyc;  bit fin;
    cyc = 0;  fin = 0;
    @(negedge clk); req_valid = 1; req_addr = line * LINE_WORDS + off;
    while (!fin) begin
      @(posedge clk); cyc++;
      if (resp_valid) begin
        if (resp_rdata !== word_val(line * LINE_WORDS + off)) begin e++; $display("FAIL [V=%0d] line %0d word %0d: %h", VICT, line, off, resp_rdata); end
        fin = 1;
      end else if (cyc > 100) begin e++; $display("FAIL [V=%0d] timeout", VICT); fin = 1; end
    end
    total_cycles += cyc;
    @(negedge clk); req_valid = 0;
  endtask
  task automatic fresh();
    @(negedge clk); local_rst = 1;  @(negedge clk); @(negedge clk); local_rst = 0;  total_cycles = 0;
  endtask
  task automatic check(input string name, input int h, vh, m);
    if (st_l1 !== h || st_vic !== vh || st_miss !== m) begin
      e++; $display("FAIL [V=%0d] %s: l1=%0d victim=%0d miss=%0d, expected %0d/%0d/%0d", VICT, name, st_l1, st_vic, st_miss, h, vh, m);
    end
    if (total_cycles != h + 2*vh + (MEM_LAT + 3)*m) begin
      e++; $display("FAIL [V=%0d] %s: %0d cycles, expected %0d", VICT, name, total_cycles, h + 2*vh + (MEM_LAT + 3)*m);
    end
  endtask

  logic [31:0] seed = 32'd2088;
  initial begin
    int tgt_h, tgt_v, tgt_m;
    e = 0; done = 0; errors = 0; misses_random = 0;
    @(posedge rst_n);

    fresh();  for (int i = 0; i < 12; i++) access((i % 2) * 4, 0);
    if (VICT == 0) check("alt", 0, 0, 12); else check("alt", 0, 10, 2);

    fresh();  for (int i = 0; i < 12; i++) access((i % 3) * 4, 0);
    if (VICT <= 1) check("three", 0, 0, 12); else check("three", 0, 9, 3);

    fresh();
    for (int i = 0; i < 400; i++) begin
      seed = seed * 32'd1664525 + 32'd1013904223;
      access(int'(seed[31:16]) % 12, int'(seed[9:8]));
    end
    case (VICT)
      0: check("random", 134, 0, 266);
      1: check("random", 134, 32, 234);
      2: check("random", 134, 75, 191);
      default: check("random", 134, 141, 125);
    endcase
    misses_random = st_miss;
    $display("V=%0d: random trace %0d memory fetches, %0d cycles", VICT, st_miss, total_cycles);
    errors = e;  done = 1;
  end
endmodule

module tb_victim_cache;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic [3:0] d;  integer er0, er1, er2, er3, m0, m1, m2, m3;
  vc_harness #(.VICT(0)) v0 (.clk, .rst_n, .done(d[0]), .errors(er0), .misses_random(m0));
  vc_harness #(.VICT(1)) v1 (.clk, .rst_n, .done(d[1]), .errors(er1), .misses_random(m1));
  vc_harness #(.VICT(2)) v2 (.clk, .rst_n, .done(d[2]), .errors(er2), .misses_random(m2));
  vc_harness #(.VICT(4)) v4 (.clk, .rst_n, .done(d[3]), .errors(er3), .misses_random(m3));
  initial begin
    repeat (2) @(negedge clk); rst_n = 1;
    wait (d == 4'hF);
    #1;
    if (er0 + er1 + er2 + er3 == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", er0 + er1 + er2 + er3);
    $finish;
  end
endmodule
