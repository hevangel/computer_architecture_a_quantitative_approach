// Set-associative, write-back, write-allocate cache with true-LRU replacement.
// WAYS = 1 gives a direct-mapped cache.  SETS, WAYS and LINE_WORDS must be powers of
// two, and SETS >= 2.
//
// CPU side  : valid/ready-style.  Hold req_* stable until resp_valid is seen.
//             resp_valid is combinational: it is high in the cycle a hit is served.
// Memory side: whole-line transfers.  mem_valid stays high until mem_done pulses.
//             mem_addr is the byte address of the first word of the line.
module set_assoc_cache #(
    parameter int SETS       = 4,
    parameter int WAYS       = 2,
    parameter int LINE_WORDS = 4,
    parameter int ADDR_W     = 16,   // byte address
    parameter int DATA_W     = 32
) (
    input  logic                          clk,
    input  logic                          rst_n,
    // CPU side
    input  logic                          req_valid,
    input  logic                          req_we,
    input  logic [ADDR_W-1:0]             req_addr,
    input  logic [DATA_W-1:0]             req_wdata,
    output logic                          resp_valid,
    output logic [DATA_W-1:0]             resp_rdata,
    // Memory side
    output logic                          mem_valid,
    output logic                          mem_we,
    output logic [ADDR_W-1:0]             mem_addr,
    output logic [LINE_WORDS*DATA_W-1:0]  mem_wdata,
    input  logic                          mem_done,
    input  logic [LINE_WORDS*DATA_W-1:0]  mem_rdata,
    // Statistics
    output logic [31:0]                   stat_hits,
    output logic [31:0]                   stat_misses,
    output logic [31:0]                   stat_writebacks
);
  localparam int BYTE_W = $clog2(DATA_W / 8);
  localparam int OFF_W  = $clog2(LINE_WORDS);
  localparam int IDX_W  = $clog2(SETS);
  localparam int TAG_W  = ADDR_W - IDX_W - OFF_W - BYTE_W;
  localparam int WAY_W  = (WAYS > 1) ? $clog2(WAYS) : 1;

  typedef enum logic [1:0] {S_IDLE, S_WRITEBACK, S_REFILL} state_t;
  state_t state;

  // Storage, flattened so that Icarus and Verilator both handle it: entry = set*WAYS + way
  logic [DATA_W-1:0]  data  [0:SETS*WAYS*LINE_WORDS-1];
  logic [TAG_W-1:0]   tags  [0:SETS*WAYS-1];
  logic               valid [0:SETS*WAYS-1];
  logic               dirty [0:SETS*WAYS-1];
  logic [WAY_W-1:0]   age   [0:SETS*WAYS-1];                // 0 = MRU ... WAYS-1 = LRU

  // Address decomposition
  logic [IDX_W-1:0]   idx;
  logic [TAG_W-1:0]   tag;
  logic [OFF_W-1:0]   woff;
  always_comb begin
    woff = req_addr[BYTE_W +: OFF_W];
    idx  = req_addr[BYTE_W + OFF_W +: IDX_W];
    tag  = req_addr[ADDR_W-1 -: TAG_W];
  end

  // Lookup
  logic             hit;
  logic [WAY_W-1:0] hit_way, victim;
  logic             victim_found;
  always_comb begin
    hit = 1'b0; hit_way = '0;
    for (int w = 0; w < WAYS; w++)
      if (valid[idx*WAYS + w] && tags[idx*WAYS + w] == tag) begin
        hit = 1'b1; hit_way = WAY_W'(w);
      end
    // victim: first invalid way, else the LRU way
    victim = '0; victim_found = 1'b0;
    for (int w = 0; w < WAYS; w++)
      if (!valid[idx*WAYS + w] && !victim_found) begin victim = WAY_W'(w); victim_found = 1'b1; end
    for (int w = 0; w < WAYS; w++)
      if (!victim_found && age[idx*WAYS + w] == WAY_W'(WAYS-1)) victim = WAY_W'(w);
  end

  logic [WAY_W-1:0] victim_q;       // way chosen at miss time
  logic             missed;         // current request has already missed once

  wire [31:0] vbase = (idx*WAYS + victim_q) * LINE_WORDS;
  wire [31:0] hbase = (idx*WAYS + hit_way) * LINE_WORDS;

  // CPU-side response (hit served in the same cycle)
  always_comb begin
    resp_valid = (state == S_IDLE) && req_valid && hit;
    resp_rdata = data[hbase + woff];
  end

  // Memory-side request
  always_comb begin
    mem_valid = (state != S_IDLE);
    mem_we    = (state == S_WRITEBACK);
    if (state == S_WRITEBACK)
      mem_addr = {tags[idx*WAYS + victim_q], idx, {(OFF_W+BYTE_W){1'b0}}};
    else
      mem_addr = {tag, idx, {(OFF_W+BYTE_W){1'b0}}};
    for (int k = 0; k < LINE_WORDS; k++)
      mem_wdata[k*DATA_W +: DATA_W] = data[vbase + k];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE; victim_q <= '0; missed <= 1'b0;
      stat_hits <= '0; stat_misses <= '0; stat_writebacks <= '0;
      for (int i = 0; i < SETS*WAYS; i++) begin
        valid[i] <= 1'b0; dirty[i] <= 1'b0; tags[i] <= '0; age[i] <= WAY_W'(i % WAYS);
      end
    end else begin
      case (state)
        S_IDLE: if (req_valid) begin
          if (hit) begin
            if (req_we) begin
              data[hbase + woff]      <= req_wdata;
              dirty[idx*WAYS + hit_way] <= 1'b1;
            end
            // LRU update: everyone younger than the touched way ages by one
            for (int w = 0; w < WAYS; w++)
              if (age[idx*WAYS + w] < age[idx*WAYS + hit_way]) age[idx*WAYS + w] <= age[idx*WAYS + w] + 1'b1;
            age[idx*WAYS + hit_way] <= '0;
            if (!missed) stat_hits <= stat_hits + 1;
            missed <= 1'b0;
          end else begin
            victim_q    <= victim;
            missed      <= 1'b1;
            stat_misses <= stat_misses + 1;
            state       <= (valid[idx*WAYS + victim] && dirty[idx*WAYS + victim]) ? S_WRITEBACK : S_REFILL;
          end
        end
        S_WRITEBACK: if (mem_done) begin
          stat_writebacks <= stat_writebacks + 1;
          dirty[idx*WAYS + victim_q] <= 1'b0;
          state <= S_REFILL;
        end
        S_REFILL: if (mem_done) begin
          for (int k = 0; k < LINE_WORDS; k++)
            data[vbase + k] <= mem_rdata[k*DATA_W +: DATA_W];
          tags[idx*WAYS + victim_q]  <= tag;
          valid[idx*WAYS + victim_q] <= 1'b1;
          dirty[idx*WAYS + victim_q] <= 1'b0;
          state <= S_IDLE;            // request is then served as a hit
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
