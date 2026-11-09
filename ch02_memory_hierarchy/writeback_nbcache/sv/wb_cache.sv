// Non-blocking WRITE-BACK cache with write-allocate, MSHRs and a write-back (victim) buffer (Chapter 2 / Appendix B).
//
// Organisation: direct mapped, 8 sets x 4 words of 32 bits; 8-bit word addresses = tag(3) | index(3) | offset(2); a valid bit and a DIRTY bit per line.
//   * Hits: reads answer on hit_* the next cycle; a store updates the line and sets its dirty bit -- NO memory traffic.
//   * Misses (reads AND stores: write-allocate) go through an MSHR (NM of them; HUM = 0 makes the cache blocking).  A miss to a line whose fetch has not yet
//     returned joins that MSHR as a target (up to 4 targets: loads and stores, in program order).  A request to a line whose MSHR has already returned its data
//     and is finishing stalls until the line is installed.
//   * When the line returns, its targets are processed one per cycle in order (a load answers on fill_*, a store patches the line and marks it dirty).  Then the line is
//     INSTALLED: a dirty victim is moved to the WRITE-BACK BUFFER (WBD line entries) -- off the critical path of the miss -- and written to memory when the memory port is
//     free.  Fetches win the memory port over write-backs, but a fetch of a line that is still in the write-back buffer waits until it has been written back.
//   * If the write-back buffer is full an install with a dirty victim waits.  A request that hits the index being installed in this very cycle waits one cycle.
//   * flush = 1 (cache idle) writes every dirty line back and raises flush_done when memory has them all.
module wb_cache #(
    parameter int NM  = 4,
    parameter bit HUM = 1'b1,
    parameter int WBD = 2
) (
    input  logic        clk, rst_n,
    input  logic        req_valid, req_write,
    input  logic [7:0]  req_addr,
    input  logic [31:0] req_wdata,
    input  logic [5:0]  req_id,
    output logic        req_ready,
    output logic        hit_valid,  output logic [5:0] hit_id,  output logic [31:0] hit_data,
    output logic        fill_valid, output logic [5:0] fill_id, output logic [31:0] fill_data,
    input  logic        flush,
    output logic        flush_done,
    // memory port
    output logic        mem_valid, mem_write,
    output logic [7:0]  mem_addr,
    output logic [127:0] mem_wdata,
    output logic [1:0]  mem_tag,
    input  logic        mem_ready,
    input  logic        mem_rvalid,
    input  logic [1:0]  mem_rtag,
    input  logic [127:0] mem_rline,
    output logic [31:0] stat_hit, stat_pri, stat_sec, stat_wb
);
  localparam logic [2:0] S_FREE = 3'd0, S_NEED = 3'd1, S_WAIT = 3'd2, S_FILLED = 3'd3, S_INSTALL = 3'd4;

  // ---- cache arrays ----
  logic        cv [0:7], cd [0:7];
  logic [2:0]  ctag [0:7];
  logic [31:0] cdata [0:31];
  // ---- MSHRs and their targets ----
  logic [2:0]   m_st [0:NM-1];
  logic [5:0]   m_line [0:NM-1];
  logic [2:0]   m_nt [0:NM-1], m_tp [0:NM-1];
  logic         m_dirty [0:NM-1];
  logic [127:0] m_data [0:NM-1];
  logic         t_wr [0:NM*4-1];
  logic [1:0]   t_off [0:NM*4-1];
  logic [5:0]   t_id [0:NM*4-1];
  logic [31:0]  t_data [0:NM*4-1];
  // ---- write-back buffer (circular FIFO of lines) ----
  logic [5:0]   wbl_line [0:WBD-1];
  logic [127:0] wbl_data [0:WBD-1];
  logic [3:0]   wb_head, wb_cnt;
  logic [3:0]   fidx;

  // ---- request decode ----
  logic [2:0] idx, tg;  logic [1:0] off;  logic [5:0] line;  logic hit;
  assign idx = req_addr[4:2];  assign tg = req_addr[7:5];  assign off = req_addr[1:0];  assign line = req_addr[7:2];
  assign hit = cv[idx] && (ctag[idx] == tg);

  // ---- combinational control ----
  logic any_active, free_ok, rd_sel_ok, drain_wb, merge_ok, act_match, fill_any, inst_any, inst_ok, inst_now, vict_dirty, blocked_idx;
  logic fl_act, fl_dirty, fl_push, fl_adv, push_v, acc, ok_req;
  logic [3:0] free_m, merge_m, rd_sel, fill_m, inst_m;
  logic [2:0] inst_idx;
  logic [5:0] push_line;  logic [127:0] push_data;
  logic [7:0] tgt;
  logic       elig [0:NM-1];
  logic       wb_ok [0:WBD-1];
  logic [127:0] vict_data;
  logic [127:0] pd;  logic [3:0] j4;

  always_comb begin
    for (int j = 0; j < WBD; j++) wb_ok[j] = (((4'(j) + 4'(WBD) - wb_head) % 4'(WBD)) < wb_cnt);
    any_active = 1'b0;  free_ok = 1'b0;  free_m = '0;
    for (int m = NM - 1; m >= 0; m--) begin
      if (m_st[m] != S_FREE) any_active = 1'b1; else begin free_ok = 1'b1; free_m = 4'(m); end
    end
    // fetch: state NEED, memory ready, no write-back-buffer entry for the line
    rd_sel_ok = 1'b0;  rd_sel = '0;
    for (int m = NM - 1; m >= 0; m--) begin
      elig[m] = (m_st[m] == S_NEED) && mem_ready;
      for (int j = 0; j < WBD; j++) if (wb_ok[j] && wbl_line[j] == m_line[m]) elig[m] = 1'b0;
      if (elig[m]) begin rd_sel_ok = 1'b1; rd_sel = 4'(m); end
    end
    drain_wb = (wb_cnt != 4'd0) && mem_ready && !rd_sel_ok;
    // filled MSHR: process its next target
    fill_any = 1'b0;  fill_m = '0;
    for (int m = NM - 1; m >= 0; m--) if (m_st[m] == S_FILLED) begin fill_any = 1'b1; fill_m = 4'(m); end
    tgt = 8'(int'(fill_m) * 4 + int'(m_tp[fill_m]));
    fill_valid = fill_any && !t_wr[tgt];
    fill_id    = t_id[tgt];
    fill_data  = m_data[fill_m] >> (32 * t_off[tgt]);
    // install
    inst_any = 1'b0;  inst_m = '0;
    for (int m = NM - 1; m >= 0; m--) if (m_st[m] == S_INSTALL) begin inst_any = 1'b1; inst_m = 4'(m); end
    inst_idx   = m_line[inst_m][2:0];
    vict_dirty = cv[inst_idx] && cd[inst_idx];
    inst_ok    = inst_any && (!vict_dirty || (wb_cnt < 4'(WBD)));
    inst_now   = inst_ok && !flush;
    for (int k = 0; k < 4; k++) vict_data[32*k +: 32] = cdata[int'(inst_idx)*4 + k];
    // flush
    fl_act   = flush && !any_active;
    fl_dirty = (fidx < 4'd8) && cv[fidx[2:0]] && cd[fidx[2:0]];
    fl_push  = fl_act && fl_dirty && (wb_cnt < 4'(WBD));
    fl_adv   = fl_act && (fidx < 4'd8) && (!fl_dirty || (wb_cnt < 4'(WBD)));
    flush_done = flush && (fidx == 4'd8) && (wb_cnt == 4'd0) && !any_active;
    for (int k = 0; k < 4; k++) pd[32*k +: 32] = cdata[int'(fidx[2:0])*4 + k];
    push_v    = (inst_now && vict_dirty) || fl_push;
    push_line = (inst_now && vict_dirty) ? {ctag[inst_idx], inst_idx} : {ctag[fidx[2:0]], fidx[2:0]};
    push_data = (inst_now && vict_dirty) ? vict_data : pd;
    // request
    merge_ok = 1'b0;  merge_m = '0;  act_match = 1'b0;
    for (int m = NM - 1; m >= 0; m--) begin
      if (m_st[m] != S_FREE && m_line[m] == line) act_match = 1'b1;
      if ((m_st[m] == S_NEED || m_st[m] == S_WAIT) && m_line[m] == line && m_nt[m] < 3'd4) begin merge_ok = 1'b1; merge_m = 4'(m); end
    end
    blocked_idx = inst_now && (inst_idx == idx);
    ok_req    = hit || merge_ok || (!act_match && free_ok);
    req_ready = !flush && !blocked_idx && (HUM || !any_active) && ok_req;
    acc       = req_valid && req_ready;
    // memory port
    mem_valid = 1'b0;  mem_write = 1'b0;  mem_addr = '0;  mem_wdata = '0;  mem_tag = '0;
    if (rd_sel_ok) begin mem_valid = 1'b1;  mem_addr = {m_line[rd_sel], 2'b00};  mem_tag = rd_sel[1:0]; end
    else if (drain_wb) begin
      mem_valid = 1'b1;  mem_write = 1'b1;  mem_addr = {wbl_line[wb_head % 4'(WBD)], 2'b00};  mem_wdata = wbl_data[wb_head % 4'(WBD)];
    end
  end

  logic [127:0] dtmp;
  logic [3:0]   tail;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < 8; i++) begin cv[i] <= 1'b0;  cd[i] <= 1'b0;  ctag[i] <= '0; end
      for (int i = 0; i < 32; i++) cdata[i] <= '0;
      for (int m = 0; m < NM; m++) begin m_st[m] <= S_FREE;  m_nt[m] <= '0;  m_tp[m] <= '0;  m_line[m] <= '0;  m_dirty[m] <= 1'b0; end
      wb_head <= '0;  wb_cnt <= '0;  fidx <= '0;
      hit_valid <= 1'b0;  stat_hit <= '0;  stat_pri <= '0;  stat_sec <= '0;  stat_wb <= '0;
    end else begin
      hit_valid <= 1'b0;
      if (!flush) fidx <= '0; else if (fl_adv) fidx <= fidx + 4'd1;
      // line arrives
      if (mem_rvalid) begin
        j4 = {2'b00, mem_rtag};
        m_data[j4] <= mem_rline;  m_st[j4] <= S_FILLED;  m_tp[j4] <= '0;  m_dirty[j4] <= 1'b0;
      end
      // process the next target of the oldest filled MSHR
      if (fill_any) begin
        if (t_wr[tgt]) begin
          dtmp = m_data[fill_m];  dtmp[32*t_off[tgt] +: 32] = t_data[tgt];
          m_data[fill_m] <= dtmp;  m_dirty[fill_m] <= 1'b1;
        end
        if (m_tp[fill_m] + 3'd1 == m_nt[fill_m]) m_st[fill_m] <= S_INSTALL; else m_tp[fill_m] <= m_tp[fill_m] + 3'd1;
      end
      // install a finished line
      if (inst_now) begin
        cv[inst_idx] <= 1'b1;  ctag[inst_idx] <= m_line[inst_m][5:3];  cd[inst_idx] <= m_dirty[inst_m];
        for (int k = 0; k < 4; k++) cdata[int'(inst_idx)*4 + k] <= m_data[inst_m][32*k +: 32];
        m_st[inst_m] <= S_FREE;
      end
      if (fl_push) cd[fidx[2:0]] <= 1'b0;
      // memory takes a fetch / a write-back
      if (rd_sel_ok) m_st[rd_sel] <= S_WAIT;
      if (drain_wb) begin wb_head <= (wb_head + 4'd1) % 4'(WBD);  stat_wb <= stat_wb + 1; end
      if (push_v) begin
        tail = (wb_head + wb_cnt) % 4'(WBD);
        wbl_line[tail] <= push_line;  wbl_data[tail] <= push_data;
      end
      wb_cnt <= wb_cnt + (push_v ? 4'd1 : 4'd0) - (drain_wb ? 4'd1 : 4'd0);
      // the CPU request
      if (acc) begin
        if (hit) begin
          if (!req_write) begin hit_valid <= 1'b1;  hit_id <= req_id;  hit_data <= cdata[int'(idx)*4 + int'(off)];  stat_hit <= stat_hit + 1; end
          else begin cdata[int'(idx)*4 + int'(off)] <= req_wdata;  cd[idx] <= 1'b1;  stat_hit <= stat_hit + 1; end
        end else if (merge_ok) begin
          t_wr[int'(merge_m)*4 + int'(m_nt[merge_m])] <= req_write;  t_off[int'(merge_m)*4 + int'(m_nt[merge_m])] <= off;
          t_id[int'(merge_m)*4 + int'(m_nt[merge_m])] <= req_id;  t_data[int'(merge_m)*4 + int'(m_nt[merge_m])] <= req_wdata;
          m_nt[merge_m] <= m_nt[merge_m] + 3'd1;  stat_sec <= stat_sec + 1;
        end else begin
          m_st[free_m] <= S_NEED;  m_line[free_m] <= line;  m_nt[free_m] <= 3'd1;
          t_wr[int'(free_m)*4] <= req_write;  t_off[int'(free_m)*4] <= off;  t_id[int'(free_m)*4] <= req_id;  t_data[int'(free_m)*4] <= req_wdata;
          stat_pri <= stat_pri + 1;
        end
      end
    end
  end
endmodule
