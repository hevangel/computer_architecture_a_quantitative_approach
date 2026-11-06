`timescale 1ns/1ps
module tb_set_assoc_cache;
  localparam int SETS = 4, WAYS = 2, LINE_WORDS = 4, ADDR_W = 16, DATA_W = 32, MEM_LAT = 3;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic req_valid = 0, req_we = 0;
  logic [ADDR_W-1:0] req_addr = 0;
  logic [DATA_W-1:0] req_wdata = 0;
  logic resp_valid;  logic [DATA_W-1:0] resp_rdata;
  logic mem_valid, mem_we, mem_done = 0;
  logic [ADDR_W-1:0] mem_addr;
  logic [LINE_WORDS*DATA_W-1:0] mem_wdata, mem_rdata;
  logic [31:0] hits, misses, wbs;

  set_assoc_cache #(.SETS(SETS), .WAYS(WAYS), .LINE_WORDS(LINE_WORDS), .ADDR_W(ADDR_W), .DATA_W(DATA_W)) dut (
    .clk, .rst_n, .req_valid, .req_we, .req_addr, .req_wdata, .resp_valid, .resp_rdata,
    .mem_valid, .mem_we, .mem_addr, .mem_wdata, .mem_done, .mem_rdata,
    .stat_hits(hits), .stat_misses(misses), .stat_writebacks(wbs));

  // ---- main memory: word array, fixed latency, whole-line transfers --------
  logic [DATA_W-1:0] mem [0:(1<<(ADDR_W-2))-1];
  function automatic [DATA_W-1:0] init_val(input int w); init_val = 32'hA5A50000 + w; endfunction
  initial for (int i = 0; i < (1<<(ADDR_W-2)); i++) mem[i] = init_val(i);

  int cnt = 0;
  always_ff @(posedge clk) begin
    mem_done <= 1'b0;
    if (mem_valid && !mem_done) begin
      if (cnt == MEM_LAT-1) begin
        cnt <= 0; mem_done <= 1'b1;
        for (int k = 0; k < LINE_WORDS; k++) begin
          if (mem_we) mem[(mem_addr>>2) + k] <= mem_wdata[k*DATA_W +: DATA_W];
          else        mem_rdata[k*DATA_W +: DATA_W] <= mem[(mem_addr>>2) + k];
        end
      end else cnt <= cnt + 1;
    end else cnt <= 0;
  end

  // ---- CPU-side helpers -----------------------------------------------------
  int errors = 0;
  task automatic access(input bit we, input int word, input [DATA_W-1:0] wdata, input [DATA_W-1:0] expect_rd, input bit check_rd);
    int timeout = 0;
    bit done = 0;
    @(negedge clk);
    req_valid = 1; req_we = we; req_addr = word * 4; req_wdata = wdata;
    while (!done) begin                       // (Icarus has no 'break')
      @(posedge clk);
      if (resp_valid) begin
        if (check_rd && resp_rdata !== expect_rd) begin
          errors++; $display("FAIL read word %0d: got %h expected %h", word, resp_rdata, expect_rd);
        end
        done = 1;
      end else if (++timeout > 100) begin
        errors++; $display("FAIL timeout on word %0d", word); done = 1;
      end
    end
    @(negedge clk); req_valid = 0; req_we = 0;
  endtask
  task automatic rd(input int word, input [DATA_W-1:0] expect_rd); access(0, word, 0, expect_rd, 1); endtask
  task automatic wr(input int word, input [DATA_W-1:0] v);        access(1, word, v, 0, 0); endtask

  task automatic expect_stats(input int h, input int m, input int w, input string at);
    if (hits !== h || misses !== m || wbs !== w) begin
      errors++; $display("FAIL stats after %s: hits=%0d misses=%0d wb=%0d, expected %0d/%0d/%0d", at, hits, misses, wbs, h, m, w);
    end
  endtask

  initial begin
    repeat (3) @(posedge clk); rst_n = 1;
    // 4 sets x 2 ways x 4 words.  Word w -> set (w/4)%4, tag w/16.  Words 0,16,32 collide in set 0.
    rd(0, init_val(0));  expect_stats(0, 1, 0, "R0 cold miss");
    rd(1, init_val(1));  rd(3, init_val(3));            // same line: spatial locality
    expect_stats(2, 1, 0, "R1,R3 hits");
    rd(4, init_val(4));  expect_stats(2, 2, 0, "R4 miss (next set)");
    wr(0, 32'hDEADBEEF); rd(0, 32'hDEADBEEF);           // write hit, read back
    expect_stats(4, 2, 0, "W0,R0 hits");
    rd(16, init_val(16)); rd(32, init_val(32));         // second way, then conflict: evicts dirty line 0
    expect_stats(4, 4, 1, "R16,R32: dirty eviction");
    if (mem[0] !== 32'hDEADBEEF) begin errors++; $display("FAIL write-back did not reach memory: %h", mem[0]); end
    rd(0, 32'hDEADBEEF);                                // refill sees the written-back value
    expect_stats(4, 5, 1, "R0 refill (evicts clean 16)");
    rd(16, init_val(16));                               // 32 was LRU -> evicted clean, no writeback
    expect_stats(4, 6, 1, "R16");
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
