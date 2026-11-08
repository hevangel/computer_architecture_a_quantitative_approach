// A direct-mapped cache with a small fully-associative VICTIM CACHE (Jouppi, 1990) -- Chapter 2, "reducing miss rate / miss penalty".
//
// Conflict misses happen when several hot lines map to the same set of a direct-mapped cache.  A tiny buffer next to the cache catches the
// lines that were just evicted: on an L1 miss the buffer is probed, and on a hit the two lines are SWAPPED (the victim line moves into L1, the
// L1 line moves into the buffer) without going to memory.  Read-only model (an instruction-cache-like path), word addresses.
//
//   L1 hit            : answered in the same cycle (1 cycle)
//   L1 miss, victim hit: swap in 1 edge, then the request replays as an L1 hit               (2 cycles, no memory access)
//   miss in both      : fetch the line from memory (mem_valid until mem_done), install in L1, the evicted L1 line goes into the
//                       victim buffer (replacing its LRU entry), then replay                    (MEM_LAT + 3 cycles with the testbench memory)
// VICT = 0 disables the buffer (plain direct-mapped cache).  mem_addr is a LINE number.
module victim_cache #(
    parameter int SETS       = 4,
    parameter int LINE_WORDS = 4,
    parameter int VICT       = 2,
    parameter int ADDR_W     = 16,       // word address
    parameter int DATA_W     = 32
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic                         req_valid,
    input  logic [ADDR_W-1:0]            req_addr,
    output logic                         resp_valid,
    output logic [DATA_W-1:0]            resp_rdata,
    output logic                         mem_valid,
    output logic [ADDR_W-1:0]            mem_addr,         // line number
    input  logic                         mem_done,
    input  logic [LINE_WORDS*DATA_W-1:0] mem_rdata,
    output logic [31:0]                  stat_l1_hits,
    output logic [31:0]                  stat_victim_hits,
    output logic [31:0]                  stat_misses
);
  localparam int OFF_W = $clog2(LINE_WORDS);
  localparam int IDX_W = $clog2(SETS);
  localparam int LN_W  = ADDR_W - OFF_W;
  localparam int VN    = (VICT > 0) ? VICT : 1;
  localparam int AGE_W = (VN > 1) ? $clog2(VN) : 1;

  logic [LN_W-1:0]   l1_line  [0:SETS-1];
  logic              l1_valid [0:SETS-1];
  logic [DATA_W-1:0] l1_data  [0:SETS*LINE_WORDS-1];
  logic [LN_W-1:0]   v_line   [0:VN-1];
  logic              v_valid  [0:VN-1];
  logic [DATA_W-1:0] v_data   [0:VN*LINE_WORDS-1];
  logic [AGE_W-1:0]  v_age    [0:VN-1];                // 0 = most recently used

  wire [LN_W-1:0]  line = req_addr[ADDR_W-1:OFF_W];
  wire [IDX_W-1:0] idx  = line[IDX_W-1:0];
  wire [OFF_W-1:0] woff = req_addr[OFF_W-1:0];

  typedef enum logic [0:0] {S_IDLE, S_FILL} state_t;
  state_t state;
  logic missed;

  logic              l1_hit, v_hit, have_slot;
  logic [AGE_W-1:0]  hit_j, ins_j;
  always_comb begin
    l1_hit = l1_valid[idx] && (l1_line[idx] == line);
    v_hit = 1'b0;  hit_j = '0;
    if (VICT > 0)
      for (int j = 0; j < VN; j++) if (v_valid[j] && v_line[j] == line) begin v_hit = 1'b1; hit_j = AGE_W'(j); end
    have_slot = 1'b0;  ins_j = '0;                                 // slot for an evicted line: first invalid, else LRU
    for (int j = 0; j < VN; j++) if (!v_valid[j] && !have_slot) begin ins_j = AGE_W'(j); have_slot = 1'b1; end
    for (int j = 0; j < VN; j++) if (!have_slot && v_age[j] == AGE_W'(VN - 1)) ins_j = AGE_W'(j);
  end

  assign resp_valid = (state == S_IDLE) && req_valid && l1_hit;
  assign resp_rdata = l1_data[int'(idx)*LINE_WORDS + int'(woff)];
  assign mem_valid  = (state == S_FILL);
  assign mem_addr   = ADDR_W'(line);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; missed <= 1'b0;
      stat_l1_hits <= '0; stat_victim_hits <= '0; stat_misses <= '0;
      for (int i = 0; i < SETS; i++) begin l1_valid[i] <= 1'b0; l1_line[i] <= '0; end
      for (int i = 0; i < SETS*LINE_WORDS; i++) l1_data[i] <= '0;
      for (int j = 0; j < VN; j++) begin v_valid[j] <= 1'b0; v_line[j] <= '0; v_age[j] <= AGE_W'(j); end
      for (int i = 0; i < VN*LINE_WORDS; i++) v_data[i] <= '0;
    end else begin
      case (state)
        S_IDLE: if (req_valid) begin
          if (l1_hit) begin
            if (!missed) stat_l1_hits <= stat_l1_hits + 1;
            missed <= 1'b0;
          end else if (v_hit) begin                                 // swap the victim line with the L1 line
            stat_victim_hits <= stat_victim_hits + 1;  missed <= 1'b1;
            for (int k = 0; k < LINE_WORDS; k++) begin
              l1_data[int'(idx)*LINE_WORDS + k]  <= v_data[int'(hit_j)*LINE_WORDS + k];
              v_data[int'(hit_j)*LINE_WORDS + k] <= l1_data[int'(idx)*LINE_WORDS + k];
            end
            l1_line[idx] <= v_line[hit_j];  l1_valid[idx] <= 1'b1;
            v_line[hit_j] <= l1_line[idx];  v_valid[hit_j] <= l1_valid[idx];
            for (int j = 0; j < VN; j++) if (v_age[j] < v_age[hit_j]) v_age[j] <= v_age[j] + 1'b1;
            v_age[hit_j] <= '0;
          end else begin
            stat_misses <= stat_misses + 1;  missed <= 1'b1;  state <= S_FILL;
          end
        end
        S_FILL: if (mem_done) begin
          if (VICT > 0 && l1_valid[idx]) begin                      // the evicted L1 line becomes the most recent victim
            for (int k = 0; k < LINE_WORDS; k++) v_data[int'(ins_j)*LINE_WORDS + k] <= l1_data[int'(idx)*LINE_WORDS + k];
            v_line[ins_j] <= l1_line[idx];  v_valid[ins_j] <= 1'b1;
            for (int j = 0; j < VN; j++) if (v_age[j] < v_age[ins_j]) v_age[j] <= v_age[j] + 1'b1;
            v_age[ins_j] <= '0;
          end
          for (int k = 0; k < LINE_WORDS; k++) l1_data[int'(idx)*LINE_WORDS + k] <= mem_rdata[k*DATA_W +: DATA_W];
          l1_line[idx] <= line;  l1_valid[idx] <= 1'b1;
          state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
