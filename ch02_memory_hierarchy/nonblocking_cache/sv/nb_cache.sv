// Non-blocking, write-through cache with MSHRs and a coalescing write buffer (Chapter 2: reducing miss penalty and miss rate by parallelism).
//
// Organisation: direct mapped, 8 sets x 4 words of 32 bits; 8-bit word addresses = tag(3) | index(3) | offset(2).  Write-through, no-write-allocate.
//   * Reads that hit answer on the hit port the next cycle (hit_*).  A read miss allocates a MISS STATUS HOLDING REGISTER (MSHR) -- or joins the MSHR already
//     fetching the same line (a SECONDARY miss, up to 4 waiting reads per MSHR) -- and the CPU port keeps accepting requests:
//         NM = number of MSHRs (outstanding line fetches);   HUM = 0: BLOCKING cache (nothing is accepted while any miss is outstanding)
//                                                            HUM = 1, NM = 1: hit-under-miss;   HUM = 1, NM > 1: miss-under-miss
//   * A line fetch goes to memory (mem_*) once memory is ready and no WRITE BUFFER entry still holds a write to that line (reads must see earlier writes).
//     When the line arrives it is installed and its waiting reads are answered, one per cycle, on the fill port (fill_*), possibly out of order with hits.
//   * Writes update the cache on a hit and are placed in the write buffer (WBD entries, oldest first; a write to an address already buffered is MERGED into the
//     entry).  With WBD = 0 a write is accepted only in a cycle in which memory takes it.  Memory reads win the memory port over buffered writes.
//   * A write to a line with a miss outstanding waits until that miss is finished (keeps the fetched line coherent with memory).
// req_ready is combinational and depends on the request presented.  Responses carry req_id.
module nb_cache #(
    parameter int NM  = 4,
    parameter bit HUM = 1'b1,
    parameter int WBD = 4
) (
    input  logic        clk, rst_n,
    input  logic        req_valid, req_write,
    input  logic [7:0]  req_addr,
    input  logic [31:0] req_wdata,
    input  logic [5:0]  req_id,
    output logic        req_ready,
    output logic        hit_valid,  output logic [5:0] hit_id,  output logic [31:0] hit_data,
    output logic        fill_valid, output logic [5:0] fill_id, output logic [31:0] fill_data,
    // memory port
    output logic        mem_valid, mem_write,
    output logic [7:0]  mem_addr,
    output logic [31:0] mem_wdata,
    output logic [1:0]  mem_tag,
    input  logic        mem_ready,
    input  logic        mem_rvalid,
    input  logic [1:0]  mem_rtag,
    input  logic [127:0] mem_rline,
    output logic [31:0] stat_hit, stat_pri, stat_sec
);
  localparam int WBA = (WBD < 1) ? 1 : WBD;
  localparam logic [1:0] S_FREE = 2'd0, S_NEED = 2'd1, S_WAIT = 2'd2, S_FILLED = 2'd3;

  // ---- cache arrays ----
  logic        cv [0:7];
  logic [2:0]  ctag [0:7];
  logic [31:0] cdata [0:31];
  // ---- MSHRs ----
  logic [1:0]   m_st [0:NM-1];
  logic [5:0]   m_line [0:NM-1];
  logic [2:0]   m_nt [0:NM-1], m_tp [0:NM-1];
  logic [1:0]   m_toff [0:NM*4-1];
  logic [5:0]   m_tid [0:NM*4-1];
  logic [127:0] m_data [0:NM-1];
  // ---- write buffer (circular FIFO) ----
  logic [7:0]  wb_addr [0:WBA-1];
  logic [31:0] wb_data [0:WBA-1];
  logic [3:0]  wb_head, wb_cnt;

  // ---- request decode ----
  logic [2:0] idx, tg;  logic [1:0] off;  logic [5:0] line;  logic hit;
  assign idx = req_addr[4:2];  assign tg = req_addr[7:5];  assign off = req_addr[1:0];  assign line = req_addr[7:2];
  assign hit = cv[idx] && (ctag[idx] == tg);

  // ---- combinational control ----
  logic any_active, free_ok, rd_sel_ok, drain_wr, w_blocked, merge_ok, stall_same, wbm_ok;
  logic [3:0] free_m, merge_m, rd_sel, wbm_j, fill_m;
  logic [7:0] head_addr;  logic [31:0] head_data;
  logic       elig [0:NM-1];
  logic       wb_ok [0:WBA-1];
  logic       fill_any;
  logic       acc, rd_ok, wr_ok;
  logic [3:0] j4;

  always_comb begin
    // write-buffer entry validity
    for (int j = 0; j < WBA; j++) wb_ok[j] = (WBD > 0) && (((4'(j) + 4'(WBA) - wb_head) % 4'(WBA)) < wb_cnt);
    head_addr = wb_addr[wb_head % 4'(WBA)];  head_data = wb_data[wb_head % 4'(WBA)];
    // MSHR status
    any_active = 1'b0;  free_ok = 1'b0;  free_m = '0;
    for (int m = NM - 1; m >= 0; m--) begin
      if (m_st[m] != S_FREE) any_active = 1'b1; else begin free_ok = 1'b1; free_m = 4'(m); end
    end
    // which MSHR may fetch its line now: state NEED, memory ready, no buffered write to the line
    rd_sel_ok = 1'b0;  rd_sel = '0;
    for (int m = NM - 1; m >= 0; m--) begin
      elig[m] = (m_st[m] == S_NEED) && mem_ready;
      for (int j = 0; j < WBA; j++) if (wb_ok[j] && wb_addr[j][7:2] == m_line[m]) elig[m] = 1'b0;
      if (elig[m]) begin rd_sel_ok = 1'b1; rd_sel = 4'(m); end
    end
    drain_wr = (WBD > 0) && (wb_cnt != 4'd0) && mem_ready && !rd_sel_ok;
    // fill port: oldest filled MSHR first
    fill_any = 1'b0;  fill_m = '0;
    for (int m = NM - 1; m >= 0; m--) if (m_st[m] == S_FILLED) begin fill_any = 1'b1; fill_m = 4'(m); end
    fill_valid = fill_any;
    fill_id    = m_tid[int'(fill_m)*4 + int'(m_tp[fill_m])];
    fill_data  = m_data[fill_m] >> (32 * m_toff[int'(fill_m)*4 + int'(m_tp[fill_m])]);
    // request-dependent
    merge_ok = 1'b0;  merge_m = '0;  stall_same = 1'b0;  w_blocked = 1'b0;
    for (int m = NM - 1; m >= 0; m--) begin
      if (m_st[m] != S_FREE && m_line[m] == line) w_blocked = 1'b1;
      if ((m_st[m] == S_NEED || m_st[m] == S_WAIT) && m_line[m] == line) begin
        if (m_nt[m] < 3'd4) begin merge_ok = 1'b1; merge_m = 4'(m); end else stall_same = 1'b1;
      end
    end
    wbm_ok = 1'b0;  wbm_j = '0;
    for (int j = WBA - 1; j >= 0; j--)
      if (wb_ok[j] && wb_addr[j] == req_addr && !(drain_wr && 4'(j) == wb_head)) begin wbm_ok = 1'b1; wbm_j = 4'(j); end
    rd_ok = hit || merge_ok || (!stall_same && free_ok);
    wr_ok = !w_blocked && (wbm_ok || ((WBD > 0) ? (wb_cnt < 4'(WBD)) : (mem_ready && !rd_sel_ok)));
    req_ready = (HUM || !any_active) && (req_write ? wr_ok : rd_ok);
    acc = req_valid && req_ready;
    // memory port
    mem_valid = 1'b0;  mem_write = 1'b0;  mem_addr = '0;  mem_wdata = '0;  mem_tag = '0;
    if (rd_sel_ok) begin mem_valid = 1'b1;  mem_addr = {m_line[rd_sel], 2'b00};  mem_tag = rd_sel[1:0]; end
    else if (drain_wr) begin mem_valid = 1'b1;  mem_write = 1'b1;  mem_addr = head_addr;  mem_wdata = head_data; end
    else if (WBD == 0 && acc && req_write) begin mem_valid = 1'b1;  mem_write = 1'b1;  mem_addr = req_addr;  mem_wdata = req_wdata; end
  end

  // ---- state update ----
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 8; i++) begin cv[i] <= 1'b0;  ctag[i] <= '0; end
      for (int i = 0; i < 32; i++) cdata[i] <= '0;
      for (int m = 0; m < NM; m++) begin m_st[m] <= S_FREE;  m_nt[m] <= '0;  m_tp[m] <= '0;  m_line[m] <= '0; end
      wb_head <= '0;  wb_cnt <= '0;
      hit_valid <= 1'b0;  stat_hit <= '0;  stat_pri <= '0;  stat_sec <= '0;
    end else begin
      hit_valid <= 1'b0;
      // line arrives: install it and hand it to the MSHR
      if (mem_rvalid) begin
        j4 = {2'b00, mem_rtag};
        cv[m_line[j4][2:0]] <= 1'b1;  ctag[m_line[j4][2:0]] <= m_line[j4][5:3];
        for (int k = 0; k < 4; k++) cdata[int'(m_line[j4][2:0])*4 + k] <= mem_rline[32*k +: 32];
        m_data[j4] <= mem_rline;  m_st[j4] <= S_FILLED;  m_tp[j4] <= '0;
      end
      // fill port: answer the next waiting read of the oldest filled MSHR
      if (fill_any) begin
        if (m_tp[fill_m] + 3'd1 == m_nt[fill_m]) m_st[fill_m] <= S_FREE; else m_tp[fill_m] <= m_tp[fill_m] + 3'd1;
      end
      // memory takes a line fetch
      if (rd_sel_ok) m_st[rd_sel] <= S_WAIT;
      // write buffer drains its oldest entry
      if (drain_wr) begin wb_head <= (wb_head + 4'd1) % 4'(WBA);  wb_cnt <= wb_cnt - 4'd1; end
      // the CPU request
      if (acc) begin
        if (!req_write) begin
          if (hit) begin
            hit_valid <= 1'b1;  hit_id <= req_id;  hit_data <= cdata[int'(idx)*4 + int'(off)];  stat_hit <= stat_hit + 1;
          end else if (merge_ok) begin
            m_toff[int'(merge_m)*4 + int'(m_nt[merge_m])] <= off;  m_tid[int'(merge_m)*4 + int'(m_nt[merge_m])] <= req_id;
            m_nt[merge_m] <= m_nt[merge_m] + 3'd1;  stat_sec <= stat_sec + 1;
          end else begin
            m_st[free_m] <= S_NEED;  m_line[free_m] <= line;  m_nt[free_m] <= 3'd1;
            m_toff[int'(free_m)*4] <= off;  m_tid[int'(free_m)*4] <= req_id;  stat_pri <= stat_pri + 1;
          end
        end else begin
          // a write that hits the line being replaced this very cycle must not touch the newly installed line (memory gets the write via the buffer)
          if (hit && !(mem_rvalid && m_line[{2'b00, mem_rtag}][2:0] == idx)) cdata[int'(idx)*4 + int'(off)] <= req_wdata;
          if (WBD > 0) begin
            if (wbm_ok) wb_data[wbm_j] <= req_wdata;
            else begin
              wb_addr[(wb_head + wb_cnt) % 4'(WBA)] <= req_addr;  wb_data[(wb_head + wb_cnt) % 4'(WBA)] <= req_wdata;
              wb_cnt <= drain_wr ? wb_cnt : wb_cnt + 4'd1;
            end
          end
        end
      end
    end
  end
endmodule
