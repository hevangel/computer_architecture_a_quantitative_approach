`timescale 1ns/1ps
// Four workloads on an 8-set direct-mapped cache (4-word lines), with and without the stride prefetcher.
//   unit    : pc 1, addresses 0..63 (stride 1 word: 4 accesses per line)
//   stride4 : pc 2, addresses 0,4,8,... (stride = one line: every access touches a new line), 48 accesses
//   random  : pc 3, 120 pseudo-random addresses in 0..255 (no repeating stride)
//   mix     : 40 x { stream pc 2 addr 4i ; hot variable pc 5 addr 12 ; pc 5 addr 13 }  -- the prefetches target sets that the hot line lives in (pollution)
// Expected (hits, misses, prefetches issued, prefetches useful) from an independent Python functional model.  It is exact in the GAP regime where
// every prefetch finishes before the next demand access (GAP >= 12 compute cycles between accesses):
//                 prefetch OFF               prefetch ON
//   unit      48 / 16 /  0 /  0       63 /  1 / 16 / 15
//   stride4    0 / 48 /  0 /  0       45 /  3 / 46 / 45
//   random    15 /105 /  0 /  0       15 /105 /  0 /  0     (no stride ever repeats -> nothing is prefetched, nothing is polluted)
//   mix       76 / 44 /  0 /  0      104 / 16 / 37 / 32     (5 of 37 prefetches wasted)
// Demand-wait cycles in that regime: 1 per hit + (MEM_LAT + 3 = 6) per miss.  With GAP = 0 (back-to-back accesses) the demand stream starves the
// prefetcher of idle time and a demand access can wait behind a prefetch: only data correctness is checked there; the counters are printed.
module pf_harness #(parameter bit PREFETCH = 1'b1, parameter int GAP = 12) (input logic clk, input logic rst_n, output logic done, output integer errors);
  localparam int MEM_LAT = 3, LINE_WORDS = 4;
  logic local_rst = 0;
  wire  dut_rst_n = rst_n && !local_rst;
  logic req_valid = 0;  logic [7:0] req_pc = 0;  logic [15:0] req_addr = 0;
  logic resp_valid, mem_valid, mem_done = 0;  logic [31:0] resp_rdata;  logic [15:0] mem_addr;
  logic [LINE_WORDS*32-1:0] mem_rdata;
  logic [31:0] st_h, st_m, st_i, st_u;

  stride_prefetcher #(.SETS(8), .LINE_WORDS(LINE_WORDS), .RPT(4), .THRESH(1), .PREFETCH(PREFETCH)) dut (.clk, .rst_n(dut_rst_n), .req_valid, .req_pc, .req_addr,
      .resp_valid, .resp_rdata, .mem_valid, .mem_addr, .mem_done, .mem_rdata, .stat_hits(st_h), .stat_misses(st_m), .stat_pf_issued(st_i), .stat_pf_useful(st_u));

  function automatic [31:0] word_val(input int w); word_val = 32'hFACE0000 + w; endfunction
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

  integer e;  int wait_cycles;
  task automatic access(input int pc, input int addr);
    int cyc;  bit fin;
    cyc = 0;  fin = 0;
    @(negedge clk); req_valid = 1; req_pc = pc[7:0]; req_addr = addr[15:0];
    while (!fin) begin
      @(posedge clk); cyc++;
      if (resp_valid) begin
        if (resp_rdata !== word_val(addr)) begin e++; $display("FAIL [PF=%0b GAP=%0d] addr %0d: %h", PREFETCH, GAP, addr, resp_rdata); end
        fin = 1;
      end else if (cyc > 200) begin e++; $display("FAIL [PF=%0b GAP=%0d] timeout at %0d", PREFETCH, GAP, addr); fin = 1; end
    end
    wait_cycles += cyc;
    @(negedge clk); req_valid = 0;
    repeat (GAP) @(negedge clk);                                   // compute time before the next access
  endtask
  task automatic fresh();
    @(negedge clk); local_rst = 1;  @(negedge clk); @(negedge clk); local_rst = 0;  wait_cycles = 0;
  endtask
  task automatic check(input string name, input int n, input int h, m, i, u);
    if (GAP >= 12) begin
      if (st_h !== h || st_m !== m || st_i !== i || st_u !== u) begin
        e++; $display("FAIL [PF=%0b] %s: hits=%0d misses=%0d issued=%0d useful=%0d, expected %0d/%0d/%0d/%0d", PREFETCH, name, st_h, st_m, st_i, st_u, h, m, i, u);
      end
      if (wait_cycles != h + (MEM_LAT + 3) * m) begin
        e++; $display("FAIL [PF=%0b] %s: %0d demand-wait cycles, expected %0d", PREFETCH, name, wait_cycles, h + (MEM_LAT + 3) * m);
      end
    end else if (st_h + st_m != n) begin
      e++; $display("FAIL [PF=%0b GAP=0] %s: hits+misses = %0d, expected %0d", PREFETCH, name, st_h + st_m, n);
    end
    $display("PF=%0b GAP=%2d %-8s: hits %3d  misses %3d  prefetches %2d (useful %2d)  demand-wait cycles %4d", PREFETCH, GAP, name, st_h, st_m, st_i, st_u, wait_cycles);
  endtask

  logic [31:0] seed = 32'd2090;
  initial begin
    e = 0; done = 0; errors = 0;
    @(posedge rst_n);
    fresh();  for (int a = 0; a < 64; a++) access(1, a);
    if (PREFETCH) check("unit", 64, 63, 1, 16, 15); else check("unit", 64, 48, 16, 0, 0);
    fresh();  for (int i = 0; i < 48; i++) access(2, 4 * i);
    if (PREFETCH) check("stride4", 48, 45, 3, 46, 45); else check("stride4", 48, 0, 48, 0, 0);
    fresh();
    for (int i = 0; i < 120; i++) begin seed = seed * 32'd1664525 + 32'd1013904223; access(3, int'(seed[31:16]) % 256); end
    check("random", 120, 15, 105, 0, 0);
    fresh();  for (int i = 0; i < 40; i++) begin access(2, 4 * i); access(5, 12); access(5, 13); end
    if (PREFETCH) check("mix", 120, 104, 16, 37, 32); else check("mix", 120, 76, 44, 0, 0);
    errors = e;  done = 1;
  end
endmodule

module tb_stride_prefetcher;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  logic [3:0] d;  integer er0, er1, er2, er3;
  pf_harness #(.PREFETCH(1'b0), .GAP(12)) off12 (.clk, .rst_n, .done(d[0]), .errors(er0));
  pf_harness #(.PREFETCH(1'b1), .GAP(12)) on12  (.clk, .rst_n, .done(d[1]), .errors(er1));
  pf_harness #(.PREFETCH(1'b0), .GAP(0))  off0  (.clk, .rst_n, .done(d[2]), .errors(er2));
  pf_harness #(.PREFETCH(1'b1), .GAP(0))  on0   (.clk, .rst_n, .done(d[3]), .errors(er3));
  initial begin
    repeat (2) @(negedge clk); rst_n = 1;
    wait (d == 4'hF);
    #1;
    if (er0 + er1 + er2 + er3 == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", er0 + er1 + er2 + er3);
    $finish;
  end
endmodule
