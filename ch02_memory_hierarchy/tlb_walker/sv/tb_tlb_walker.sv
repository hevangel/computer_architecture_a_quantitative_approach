`timescale 1ns/1ps
// Page table (in testbench memory): vpn 0..7 valid, ppn = 0x100 + 3*vpn; vpn 5 and 6 are read-only; vpn >= 8 invalid.
// Every response is checked against the page table alone (paddr / fault flags); the hit / miss / fault totals
// are checked against an independent Python LRU model: directed part (5, 10, 4), whole run (130, 185, 93).
module tb_tlb_walker;
  localparam int PT_LAT = 2;
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  logic req_valid = 0, req_write = 0;  logic [31:0] req_vaddr = 0;
  logic resp_valid, resp_page_fault, resp_prot_fault, pt_valid, pt_done = 0;
  logic [31:0] resp_paddr, pt_addr, pt_rdata, hits, misses, faults;

  tlb_walker #(.ENTRIES(4), .PT_BASE(32'h0)) dut (.*, .stat_hits(hits), .stat_misses(misses), .stat_faults(faults));

  // ---- page table + walker memory model --------------------------------------------------------
  logic [31:0] pt [0:63];
  function automatic logic [31:0] pte_of(input int v);
    if (v < 8) pte_of = ((32'h100 + 3*v) << 12) | ((v == 5 || v == 6) ? 32'h0 : 32'h2) | 32'h1;
    else       pte_of = 32'h0;
  endfunction
  initial for (int i = 0; i < 64; i++) pt[i] = pte_of(i);
  int cnt = 0;
  always_ff @(posedge clk) begin
    pt_done <= 1'b0;
    if (pt_valid && !pt_done) begin
      if (cnt == PT_LAT-1) begin cnt <= 0; pt_done <= 1'b1; pt_rdata <= pt[pt_addr >> 2]; end else cnt <= cnt + 1;
    end else cnt <= 0;
  end

  int errors = 0;
  task automatic access(input int vpn, input bit wr, input int off);
    logic [31:0] exp_pa;  bit exp_pf, exp_prot;  int timeout;  bit done;
    exp_pf   = (vpn >= 8);
    exp_prot = !exp_pf && wr && (vpn == 5 || vpn == 6);
    exp_pa   = ((32'h100 + 3*vpn) << 12) | off;
    timeout = 0;  done = 0;
    @(negedge clk); req_valid = 1; req_write = wr; req_vaddr = (vpn << 12) | off;
    while (!done) begin
      @(posedge clk);
      if (resp_valid) begin
        if (resp_page_fault !== exp_pf || resp_prot_fault !== exp_prot) begin
          errors++; $display("FAIL vpn %0d wr=%0b: faults pf=%b prot=%b, expected %b %b", vpn, wr, resp_page_fault, resp_prot_fault, exp_pf, exp_prot);
        end else if (!exp_pf && resp_paddr !== exp_pa) begin
          errors++; $display("FAIL vpn %0d: paddr %h expected %h", vpn, resp_paddr, exp_pa);
        end
        done = 1;
      end else if (++timeout > 50) begin errors++; $display("FAIL timeout vpn %0d", vpn); done = 1; end
    end
    @(negedge clk); req_valid = 0; req_write = 0;
  endtask

  task automatic expect_stats(input int h, m, f, input string at);
    if (hits !== h || misses !== m || faults !== f) begin
      errors++; $display("FAIL stats after %s: hits=%0d misses=%0d faults=%0d, expected %0d/%0d/%0d", at, hits, misses, faults, h, m, f);
    end
  endtask

  logic [31:0] seed = 32'd2002;
  initial begin
    repeat (3) @(posedge clk); rst_n = 1;
    // directed: 4-entry fully associative TLB, LRU
    access(0, 0, 32'h010);  access(0, 0, 32'h7F0);                 // miss (walk), hit
    access(1, 0, 0); access(2, 0, 0); access(3, 0, 0);              // fill the other three entries
    access(0, 0, 4);                                                 // hit: vpn 0 becomes MRU, vpn 1 is now LRU
    access(4, 0, 0);                                                 // miss: evicts vpn 1
    access(1, 0, 0);                                                 // miss again (it was evicted); evicts vpn 2
    access(0, 0, 8);                                                 // hit: vpn 0 still resident
    access(5, 1, 0);                                                 // read-only page written: walk, install, protection fault
    access(5, 0, 0);                                                 // read of the same page: hit
    access(5, 1, 0);                                                 // write again: hit, protection fault
    access(9, 0, 0);  access(9, 1, 0);                               // invalid pages: page fault each time (nothing installed)
    access(2, 0, 0);
    expect_stats(5, 10, 4, "directed part");
    // pseudo-random mix of 12 pages (4 invalid), reads and writes
    for (int i = 0; i < 300; i++) begin
      seed = seed * 32'd1664525 + 32'd1013904223;
      access(int'(seed[19:16]) % 12, seed[24], int'(seed[11:0]));
    end
    expect_stats(130, 185, 93, "whole run");
    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
