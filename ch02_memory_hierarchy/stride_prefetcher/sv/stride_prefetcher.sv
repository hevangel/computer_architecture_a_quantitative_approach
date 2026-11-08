// A direct-mapped cache with a hardware STRIDE PREFETCHER (reference prediction table, Chen & Baer) -- Chapter 2, "reducing miss penalty or miss rate via parallelism".
//
// Every demand access carries the program counter of the load/store.  A small table indexed by PC remembers, per instruction, the last address,
// the last stride and a confidence counter:
//     new stride == remembered stride (and != 0)  ->  confidence + 1 (saturates at 2)          else  stride := new stride, confidence := 0
// When confidence >= THRESH (two consecutive equal strides), the cache prefetches the line containing  address + stride.
//   * Demand accesses have priority: a prefetch starts only when the cache is idle, and a demand request that arrives during a prefetch waits for it.
//   * A prefetched line is installed in the cache with a "prefetched" bit.  stat_pf_useful counts the first demand hit on such a line;
//     stat_pf_issued counts prefetches sent to memory (a target line already in the cache is dropped, not counted).
//     accuracy = useful / issued;   a prefetch evicting a live line is cache POLLUTION.
//   * PREFETCH = 0 gives the plain cache for comparison.  Words are addressed by word number; mem_addr is a LINE number.
// Timing: hit 1 cycle; miss MEM_LAT + 3 cycles with the testbench memory (as in victim_cache).
module stride_prefetcher #(
    parameter int SETS       = 8,
    parameter int LINE_WORDS = 4,
    parameter int RPT        = 4,         // reference-prediction-table entries (indexed by PC low bits)
    parameter int THRESH     = 1,
    parameter bit PREFETCH   = 1'b1,
    parameter int ADDR_W     = 16,
    parameter int DATA_W     = 32
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         req_valid,
    input  logic [7:0]                   req_pc,
    input  logic [ADDR_W-1:0]            req_addr,
    output logic                         resp_valid,
    output logic [DATA_W-1:0]            resp_rdata,
    output logic                         mem_valid,
    output logic [ADDR_W-1:0]            mem_addr,         // line number
    input  logic                         mem_done,
    input  logic [LINE_WORDS*DATA_W-1:0] mem_rdata,
    output logic [31:0]                  stat_hits,        // demand accesses served without a miss (includes hits on prefetched lines)
    output logic [31:0]                  stat_misses,
    output logic [31:0]                  stat_pf_issued,
    output logic [31:0]                  stat_pf_useful
);
  localparam int OFF_W = $clog2(LINE_WORDS);
  localparam int IDX_W = $clog2(SETS);
  localparam int RIDX  = $clog2(RPT);
  localparam int LN_W  = ADDR_W - OFF_W;
  localparam int SW    = ADDR_W + 1;                          // signed width for strides / targets

  typedef enum logic [1:0] {S_IDLE, S_DFILL, S_PFILL} state_t;
  state_t state;

  logic [LN_W-1:0]   c_line  [0:SETS-1];
  logic              c_valid [0:SETS-1];
  logic              c_pf    [0:SETS-1];
  logic [DATA_W-1:0] c_data  [0:SETS*LINE_WORDS-1];
  logic              r_valid [0:RPT-1];
  logic [ADDR_W-1:0] r_last  [0:RPT-1];
  logic signed [SW-1:0] r_stride [0:RPT-1];
  logic [1:0]        r_conf  [0:RPT-1];

  logic              pf_pending;
  logic [LN_W-1:0]   pf_line;                                 // target of the pending prefetch
  logic [LN_W-1:0]   pf_cur;                                  // line being prefetched
  logic              missed;

  wire [LN_W-1:0]  line = req_addr[ADDR_W-1:OFF_W];
  wire [IDX_W-1:0] idx  = line[IDX_W-1:0];
  wire [OFF_W-1:0] woff = req_addr[OFF_W-1:0];
  wire             hit  = c_valid[idx] && (c_line[idx] == line);
  wire [IDX_W-1:0] pf_idx = pf_line[IDX_W-1:0];
  wire             pf_resident = c_valid[pf_idx] && (c_line[pf_idx] == pf_line);

  assign resp_valid = (state == S_IDLE) && req_valid && hit;
  assign resp_rdata = c_data[int'(idx)*LINE_WORDS + int'(woff)];
  assign mem_valid  = (state != S_IDLE);
  assign mem_addr   = (state == S_PFILL) ? ADDR_W'(pf_cur) : ADDR_W'(line);

  // ---- training (combinational view of the table entry touched by this access) --------------------------
  logic [RIDX-1:0]      k;
  logic signed [SW-1:0] ns, nstride, target;
  logic [1:0]           nconf;
  logic                 want_pf;
  always_comb begin
    k  = req_pc[RIDX-1:0];
    ns = $signed({1'b0, req_addr}) - $signed({1'b0, r_last[k]});
    if (r_valid[k] && ns == r_stride[k] && ns != '0) begin nstride = r_stride[k]; nconf = (r_conf[k] == 2'd2) ? 2'd2 : r_conf[k] + 2'd1; end
    else begin nstride = r_valid[k] ? ns : '0; nconf = 2'd0; end
    target  = $signed({1'b0, req_addr}) + nstride;
    want_pf = PREFETCH && r_valid[k] && (int'(nconf) >= THRESH) && !target[SW-1] && (target[SW-1:0] < (1 << ADDR_W));
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; missed <= 1'b0; pf_pending <= 1'b0; pf_line <= '0; pf_cur <= '0;
      stat_hits <= '0; stat_misses <= '0; stat_pf_issued <= '0; stat_pf_useful <= '0;
      for (int i = 0; i < SETS; i++) begin c_valid[i] <= 1'b0; c_pf[i] <= 1'b0; c_line[i] <= '0; end
      for (int i = 0; i < SETS*LINE_WORDS; i++) c_data[i] <= '0;
      for (int i = 0; i < RPT; i++) begin r_valid[i] <= 1'b0; r_last[i] <= '0; r_stride[i] <= '0; r_conf[i] <= '0; end
    end else begin
      case (state)
        S_IDLE: begin
          if (req_valid) begin                                          // demand has priority
            if (hit) begin
              if (!missed) stat_hits <= stat_hits + 1;
              if (c_pf[idx]) begin stat_pf_useful <= stat_pf_useful + 1; c_pf[idx] <= 1'b0; end
              missed <= 1'b0;
              r_valid[k] <= 1'b1;  r_last[k] <= req_addr;  r_stride[k] <= nstride;  r_conf[k] <= nconf;   // train once per request
              if (want_pf) begin pf_pending <= 1'b1; pf_line <= target[ADDR_W-1:OFF_W]; end
            end else begin
              stat_misses <= stat_misses + 1;  missed <= 1'b1;  state <= S_DFILL;
            end
          end else if (pf_pending) begin
            pf_pending <= 1'b0;
            if (!pf_resident) begin pf_cur <= pf_line; stat_pf_issued <= stat_pf_issued + 1; state <= S_PFILL; end
          end
        end
        S_DFILL: if (mem_done) begin
          for (int w = 0; w < LINE_WORDS; w++) c_data[int'(idx)*LINE_WORDS + w] <= mem_rdata[w*DATA_W +: DATA_W];
          c_line[idx] <= line;  c_valid[idx] <= 1'b1;  c_pf[idx] <= 1'b0;
          state <= S_IDLE;
        end
        S_PFILL: if (mem_done) begin
          for (int w = 0; w < LINE_WORDS; w++) c_data[int'(pf_cur[IDX_W-1:0])*LINE_WORDS + w] <= mem_rdata[w*DATA_W +: DATA_W];
          c_line[pf_cur[IDX_W-1:0]] <= pf_cur;  c_valid[pf_cur[IDX_W-1:0]] <= 1'b1;  c_pf[pf_cur[IDX_W-1:0]] <= 1'b1;
          state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
