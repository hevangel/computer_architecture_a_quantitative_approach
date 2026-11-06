// Fully-associative TLB with true-LRU replacement and a hardware page-table walker (Chapter 2 / Appendix B).
//
// Virtual address (32 bit) = { VPN (20) | page offset (12) }.  A one-level page table starts at PT_BASE; the
// PTE for page `vpn` is the word at PT_BASE + 4*vpn:
//     PTE[31:12] = physical page number    PTE[1] = W (writable)    PTE[0] = V (valid)
//
// Protocol (same as the cache): hold req_* until resp_valid.  A TLB hit answers in the same cycle.
//   miss          -> the walker reads the PTE (pt_valid stays high until pt_done pulses);
//   V = 1         -> the entry is installed and the request is replayed as a hit;
//   V = 0         -> resp_valid with resp_page_fault (nothing is installed);
//   write to W = 0 -> resp_valid with resp_prot_fault (hit or just walked).
// Statistics: hits = requests served by the TLB without a walk, misses = walks started, faults = page + protection faults.
module tlb_walker #(
    parameter int ENTRIES = 4,          // power of two
    parameter logic [31:0] PT_BASE = 32'h0
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        req_valid,
    input  logic        req_write,
    input  logic [31:0] req_vaddr,
    output logic        resp_valid,
    output logic [31:0] resp_paddr,
    output logic        resp_page_fault,
    output logic        resp_prot_fault,
    // page-table walker memory port
    output logic        pt_valid,
    output logic [31:0] pt_addr,
    input  logic        pt_done,
    input  logic [31:0] pt_rdata,
    output logic [31:0] stat_hits,
    output logic [31:0] stat_misses,
    output logic [31:0] stat_faults
);
  localparam int EW = $clog2(ENTRIES);
  typedef enum logic [1:0] {S_IDLE, S_WALK, S_FAULT} state_t;
  state_t state;

  logic [19:0]   e_vpn   [0:ENTRIES-1];
  logic [19:0]   e_ppn   [0:ENTRIES-1];
  logic          e_w     [0:ENTRIES-1];
  logic          e_valid [0:ENTRIES-1];
  logic [EW-1:0] e_age   [0:ENTRIES-1];                 // 0 = most recently used

  wire [19:0] vpn = req_vaddr[31:12];
  logic          hit;
  logic [EW-1:0] hit_e, victim;
  logic          have_victim;
  always_comb begin
    hit = 1'b0; hit_e = '0;
    for (int i = 0; i < ENTRIES; i++)
      if (e_valid[i] && e_vpn[i] == vpn) begin hit = 1'b1; hit_e = EW'(i); end
    victim = '0; have_victim = 1'b0;
    for (int i = 0; i < ENTRIES; i++)
      if (!e_valid[i] && !have_victim) begin victim = EW'(i); have_victim = 1'b1; end
    for (int i = 0; i < ENTRIES; i++)
      if (!have_victim && e_age[i] == EW'(ENTRIES-1)) victim = EW'(i);
  end

  logic [EW-1:0] victim_q;
  logic          missed;
  wire prot = req_write && !e_w[hit_e];

  always_comb begin
    resp_valid      = 1'b0;
    resp_page_fault = 1'b0;
    resp_prot_fault = 1'b0;
    resp_paddr      = {e_ppn[hit_e], req_vaddr[11:0]};
    if (state == S_IDLE && req_valid && hit) begin resp_valid = 1'b1; resp_prot_fault = prot; end
    if (state == S_FAULT)                    begin resp_valid = 1'b1; resp_page_fault = 1'b1; end
    pt_valid = (state == S_WALK);
    pt_addr  = PT_BASE + {10'b0, vpn, 2'b00};
  end

  // LRU update: every entry younger than the touched one ages by one; the touched one becomes MRU
  task automatic touch(input logic [EW-1:0] t);
    for (int i = 0; i < ENTRIES; i++)
      if (e_age[i] < e_age[t]) e_age[i] <= e_age[i] + 1'b1;
    e_age[t] <= '0;
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; victim_q <= '0; missed <= 1'b0;
      stat_hits <= '0; stat_misses <= '0; stat_faults <= '0;
      for (int i = 0; i < ENTRIES; i++) begin
        e_valid[i] <= 1'b0; e_vpn[i] <= '0; e_ppn[i] <= '0; e_w[i] <= 1'b0; e_age[i] <= EW'(i);
      end
    end else begin
      case (state)
        S_IDLE: if (req_valid) begin
          if (hit) begin
            touch(hit_e);
            if (!missed) stat_hits <= stat_hits + 1;
            if (prot)    stat_faults <= stat_faults + 1;
            missed <= 1'b0;
          end else begin
            victim_q <= victim; missed <= 1'b1; stat_misses <= stat_misses + 1; state <= S_WALK;
          end
        end
        S_WALK: if (pt_done) begin
          if (pt_rdata[0]) begin                              // valid PTE: install, then the request replays as a hit
            e_valid[victim_q] <= 1'b1; e_vpn[victim_q] <= vpn; e_ppn[victim_q] <= pt_rdata[31:12]; e_w[victim_q] <= pt_rdata[1];
            touch(victim_q);
            state <= S_IDLE;
          end else state <= S_FAULT;
        end
        S_FAULT: begin
          stat_faults <= stat_faults + 1; missed <= 1'b0; state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
