// A DRAM memory controller (Chapter 2: memory technology and organisation; Appendix B on DRAM timing).
//
// A request queue feeds a command scheduler that drives ONE command per cycle to a 4-bank DRAM (see dram_device).  The controller:
//   * tracks the open row of every bank (the ROW BUFFER) and the timing constraints between commands with down-counters:
//         tRCD (ACT->RD/WR)  tRAS (ACT->PRE)  tRP (PRE->ACT)  tRTP (RD->PRE)  tWR (write data->PRE)  tRRD (ACT->ACT)
//         tCCD (column->column)  tWTR (write data->RD)  tRTW (RD->WR)  tRFC (REF->ACT)  and REFRESH every tREFI;
//   * SCHEDULES either FCFS (only the oldest request may make progress) or FR-FCFS ("first-ready, first-come-first-served"): among the requests whose next
//     command can issue, row-buffer HITS go first, then the oldest request; a row is not closed while a queued request still hits it;
//   * never reorders two requests to the same burst address (read-after-write etc. keep program order);
//   * applies an OPEN-page policy (leave the row open until a conflict or a refresh) or a CLOSED-page policy (precharge a bank as soon as nothing queued hits its row);
//   * every tREFI cycles stops new work, precharges the open banks, issues REF, and resumes after tRFC.
// Requests are one burst (128 bits) at a burst address {row[3:0], bank[1:0], col[1:0]}.  Reads answer on rd_resp_* when the data arrives; writes answer on wr_resp_*
// (tCWL + BL cycles after the WR command).  Latencies, request accepted at cycle q (idle controller, constraints long satisfied):
//     row hit   : q + 2 + tCL + BL                     row miss (bank closed): q + 2 + tRCD + tCL + BL        row conflict: q + 2 + tRP + tRCD + tCL + BL
// (the "2" is the pipeline: queue write, command decision, registered command output).
module dram_ctrl #(
    parameter int QD   = 8,
    parameter int BL   = 4,
    parameter int tRCD = 3, parameter int tCL = 3, parameter int tCWL = 2, parameter int tRP = 3, parameter int tRAS = 7,
    parameter int tWR = 3, parameter int tRTP = 2, parameter int tRRD = 2, parameter int tCCD = 4, parameter int tWTR = 3,
    parameter int tRTW = 6, parameter int tRFC = 12, parameter int tREFI = 200,
    parameter bit FR_FCFS   = 1'b1,
    parameter bit OPEN_PAGE = 1'b1
) (
    input  logic         clk,
    input  logic         rst_n,
    // requests
    input  logic         req_valid,
    output logic         req_ready,
    input  logic         req_write,
    input  logic [7:0]   req_addr,
    input  logic [127:0] req_wdata,
    input  logic [5:0]   req_id,
    // responses
    output logic         rd_resp_valid,
    output logic [5:0]   rd_resp_id,
    output logic [127:0] rd_resp_data,
    output logic         wr_resp_valid,
    output logic [5:0]   wr_resp_id,
    // DRAM command bus
    output logic         cmd_valid,
    output logic [2:0]   cmd,
    output logic [1:0]   cmd_bank,
    output logic [3:0]   cmd_row,
    output logic [1:0]   cmd_col,
    output logic [127:0] cmd_wdata,
    input  logic         dev_rd_valid,
    input  logic [127:0] dev_rd_data,
    output logic [31:0]  stat_act, stat_pre, stat_rd, stat_wr, stat_ref
);
  localparam logic [2:0] C_ACT = 3'd1, C_RD = 3'd2, C_WR = 3'd3, C_PRE = 3'd4, C_REF = 3'd5;
  localparam int QI = $clog2(QD);

  // ---- request queue ------------------------------------------------------------------------------------
  logic              q_valid [0:QD-1];
  logic              q_write [0:QD-1];
  logic [7:0]        q_addr  [0:QD-1];
  logic [127:0]      q_wdata [0:QD-1];
  logic [5:0]        q_id    [0:QD-1];
  logic [15:0]       q_seq   [0:QD-1];
  logic [15:0]       seq_ctr;

  // ---- bank state and timing counters (a command is allowed when its counter is 0) ----------------------------------
  logic [3:0]  b_row [0:3];
  logic        b_open [0:3];
  logic [7:0]  c_col [0:3], c_pre [0:3], c_act [0:3];
  logic [7:0]  c_ccd, c_rrd, c_wtr, c_rtw;
  logic [15:0] refi_cnt;
  logic        ref_pending;

  // ---- in-flight responses ----------------------------------------------------------------------------------------
  logic [5:0]  rid [0:3];  logic [1:0] r_head, r_tail;  logic [2:0] r_count;      // read ids, in issue order
  logic [7:0]  w_cnt [0:3];  logic [5:0] w_id [0:3];                              // write acks counting down

  // ---- scheduler (combinational) ------------------------------------------------------------------------------------
  logic              free_v;  logic [QI-1:0] free_idx;
  logic              have_cmd;  logic [2:0] sel_cmd;  logic [1:0] sel_bank;  logic [3:0] sel_row;  logic [1:0] sel_col;  logic [QI-1:0] sel_idx;  logic sel_is_col;
  logic              col_found, oth_found;  logic [15:0] col_seq, oth_seq;
  logic [QI-1:0]     col_idx, oth_idx;  logic [2:0] oth_cmd;
  logic              ha, ob, hz, is_old, hit, col_ok, act_ok, pre_ok, other_hit, elig;
  logic [1:0]        bb;  logic [3:0] rr;
  logic              any_open, pre_found;  logic [1:0] pre_bank;
  logic              hit_pending;

  always_comb begin
    free_v = 1'b0;  free_idx = '0;
    for (int i = QD - 1; i >= 0; i--) if (!q_valid[i]) begin free_v = 1'b1; free_idx = QI'(i); end
    req_ready = free_v;

    col_found = 1'b0;  oth_found = 1'b0;  col_seq = '1;  oth_seq = '1;  col_idx = '0;  oth_idx = '0;  oth_cmd = 3'd0;
    ha = 1'b0; ob = 1'b0; hz = 1'b0; is_old = 1'b0; hit = 1'b0; col_ok = 1'b0; act_ok = 1'b0; pre_ok = 1'b0; other_hit = 1'b0; elig = 1'b0; bb = '0; rr = '0;
    for (int i = 0; i < QD; i++) if (q_valid[i]) begin
      bb = q_addr[i][3:2];  rr = q_addr[i][7:4];
      hz = 1'b0;  is_old = 1'b1;
      for (int j = 0; j < QD; j++) if (q_valid[j] && q_seq[j] < q_seq[i]) begin
        is_old = 1'b0;
        if (q_addr[j] == q_addr[i]) hz = 1'b1;                                        // an older request to the same burst: keep program order
      end
      elig   = FR_FCFS ? !hz : is_old;
      hit    = b_open[bb] && (b_row[bb] == rr);
      col_ok = hit && (c_col[bb] == 8'd0) && (c_ccd == 8'd0) && (q_write[i] ? (c_rtw == 8'd0) : (c_wtr == 8'd0));
      act_ok = !b_open[bb] && (c_act[bb] == 8'd0) && (c_rrd == 8'd0);
      other_hit = 1'b0;                                                                // does any queued request still hit the open row of this bank?
      for (int k = 0; k < QD; k++) if (q_valid[k] && q_addr[k][3:2] == bb && b_open[bb] && b_row[bb] == q_addr[k][7:4]) other_hit = 1'b1;
      pre_ok = b_open[bb] && (b_row[bb] != rr) && (c_pre[bb] == 8'd0) && (FR_FCFS ? !other_hit : 1'b1);
      if (elig && col_ok && q_seq[i] < col_seq) begin col_found = 1'b1; col_seq = q_seq[i]; col_idx = QI'(i); end
      if (elig && (act_ok || pre_ok) && q_seq[i] < oth_seq) begin
        oth_found = 1'b1; oth_seq = q_seq[i]; oth_idx = QI'(i); oth_cmd = act_ok ? C_ACT : C_PRE;
      end
    end

    // closed-page / refresh helpers
    any_open = 1'b0;  pre_found = 1'b0;  pre_bank = '0;
    for (int b = 3; b >= 0; b--) begin
      if (b_open[b]) any_open = 1'b1;
      hit_pending = 1'b0;
      for (int k = 0; k < QD; k++) if (q_valid[k] && q_addr[k][3:2] == 2'(b) && b_row[b] == q_addr[k][7:4]) hit_pending = 1'b1;
      if (b_open[b] && c_pre[b] == 8'd0 && (ref_pending || (!OPEN_PAGE && !hit_pending))) begin pre_found = 1'b1; pre_bank = 2'(b); end
    end

    // pick the command
    have_cmd = 1'b0;  sel_cmd = 3'd0;  sel_bank = '0;  sel_row = '0;  sel_col = 2'b0;  sel_idx = '0;  sel_is_col = 1'b0;
    if (ref_pending) begin
      if (pre_found) begin have_cmd = 1'b1; sel_cmd = C_PRE; sel_bank = pre_bank; end
      else if (!any_open && c_act[0] == 8'd0 && c_act[1] == 8'd0 && c_act[2] == 8'd0 && c_act[3] == 8'd0) begin have_cmd = 1'b1; sel_cmd = C_REF; end
    end else if (col_found) begin
      have_cmd = 1'b1;  sel_idx = col_idx;  sel_is_col = 1'b1;  sel_cmd = q_write[col_idx] ? C_WR : C_RD;
      sel_bank = q_addr[col_idx][3:2];  sel_row = q_addr[col_idx][7:4];  sel_col = q_addr[col_idx][1:0];
    end else if (oth_found) begin
      have_cmd = 1'b1;  sel_idx = oth_idx;  sel_cmd = oth_cmd;
      sel_bank = q_addr[oth_idx][3:2];  sel_row = q_addr[oth_idx][7:4];  sel_col = q_addr[oth_idx][1:0];
      if (oth_cmd == C_PRE) sel_row = b_row[q_addr[oth_idx][3:2]];
    end else if (pre_found) begin                                                      // closed-page: close an idle open bank
      have_cmd = 1'b1;  sel_cmd = C_PRE;  sel_bank = pre_bank;
    end
  end

  // ---- responses --------------------------------------------------------------------------------------------------
  always_comb begin
    rd_resp_valid = dev_rd_valid;  rd_resp_id = rid[r_head];  rd_resp_data = dev_rd_data;
    wr_resp_valid = 1'b0;  wr_resp_id = '0;
    for (int s = 0; s < 4; s++) if (w_cnt[s] == 8'd1) begin wr_resp_valid = 1'b1; wr_resp_id = w_id[s]; end
  end

  function automatic logic [7:0] max8(input logic [7:0] x, input logic [7:0] y); max8 = (x > y) ? x : y; endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cmd_valid <= 1'b0; cmd <= '0; cmd_bank <= '0; cmd_row <= '0; cmd_col <= 2'b0; cmd_wdata <= '0;
      seq_ctr <= '0; refi_cnt <= '0; ref_pending <= 1'b0; c_ccd <= '0; c_rrd <= '0; c_wtr <= '0; c_rtw <= '0;
      r_head <= '0; r_tail <= '0; r_count <= '0;
      stat_act <= '0; stat_pre <= '0; stat_rd <= '0; stat_wr <= '0; stat_ref <= '0;
      for (int i = 0; i < QD; i++) begin q_valid[i] <= 1'b0; q_write[i] <= 1'b0; q_addr[i] <= '0; q_wdata[i] <= '0; q_id[i] <= '0; q_seq[i] <= '0; end
      for (int b = 0; b < 4; b++) begin b_open[b] <= 1'b0; b_row[b] <= '0; c_col[b] <= '0; c_pre[b] <= '0; c_act[b] <= '0; rid[b] <= '0; w_cnt[b] <= '0; w_id[b] <= '0; end
    end else begin
      // counters tick down
      for (int b = 0; b < 4; b++) begin
        if (c_col[b] != 8'd0) c_col[b] <= c_col[b] - 8'd1;
        if (c_pre[b] != 8'd0) c_pre[b] <= c_pre[b] - 8'd1;
        if (c_act[b] != 8'd0) c_act[b] <= c_act[b] - 8'd1;
        if (w_cnt[b] != 8'd0) w_cnt[b] <= w_cnt[b] - 8'd1;
      end
      if (c_ccd != 8'd0) c_ccd <= c_ccd - 8'd1;
      if (c_rrd != 8'd0) c_rrd <= c_rrd - 8'd1;
      if (c_wtr != 8'd0) c_wtr <= c_wtr - 8'd1;
      if (c_rtw != 8'd0) c_rtw <= c_rtw - 8'd1;
      // refresh timer
      if (refi_cnt >= 16'(tREFI)) ref_pending <= 1'b1; else refi_cnt <= refi_cnt + 16'd1;
      if (dev_rd_valid) begin r_head <= r_head + 2'd1; end

      // enqueue
      if (req_valid && req_ready) begin
        q_valid[free_idx] <= 1'b1;  q_write[free_idx] <= req_write;  q_addr[free_idx] <= req_addr;
        q_wdata[free_idx] <= req_wdata;  q_id[free_idx] <= req_id;  q_seq[free_idx] <= seq_ctr;  seq_ctr <= seq_ctr + 16'd1;
      end

      // command issue
      cmd_valid <= have_cmd;  cmd <= sel_cmd;  cmd_bank <= sel_bank;  cmd_row <= sel_row;  cmd_col <= sel_col;
      cmd_wdata <= sel_is_col ? q_wdata[sel_idx] : 128'd0;
      if (have_cmd) begin
        case (sel_cmd)
          C_ACT: begin
            b_open[sel_bank] <= 1'b1;  b_row[sel_bank] <= sel_row;
            c_col[sel_bank] <= 8'(tRCD - 1);  c_pre[sel_bank] <= 8'(tRAS - 1);  c_rrd <= 8'(tRRD - 1);
            stat_act <= stat_act + 1;
          end
          C_RD: begin
            c_ccd <= 8'(tCCD - 1);  c_rtw <= 8'(tRTW - 1);  c_pre[sel_bank] <= max8(c_pre[sel_bank] - ((c_pre[sel_bank] != 0) ? 8'd1 : 8'd0), 8'(tRTP - 1));
            rid[r_tail] <= q_id[sel_idx];  r_tail <= r_tail + 2'd1;  q_valid[sel_idx] <= 1'b0;  stat_rd <= stat_rd + 1;
          end
          C_WR: begin
            c_ccd <= 8'(tCCD - 1);  c_wtr <= 8'(tCWL + BL + tWTR - 1);
            c_pre[sel_bank] <= max8(c_pre[sel_bank] - ((c_pre[sel_bank] != 0) ? 8'd1 : 8'd0), 8'(tCWL + BL + tWR - 1));
            q_valid[sel_idx] <= 1'b0;  stat_wr <= stat_wr + 1;
            begin : wslot
              int taken;  taken = 0;
              for (int s = 0; s < 4; s++) if (taken == 0 && (w_cnt[s] == 8'd0 || w_cnt[s] == 8'd1)) begin w_cnt[s] <= 8'(tCWL + BL + 1); w_id[s] <= q_id[sel_idx]; taken = 1; end
            end
          end
          C_PRE: begin
            b_open[sel_bank] <= 1'b0;  c_act[sel_bank] <= 8'(tRP - 1);  stat_pre <= stat_pre + 1;
          end
          C_REF: begin
            for (int b = 0; b < 4; b++) c_act[b] <= 8'(tRFC - 1);
            ref_pending <= 1'b0;  refi_cnt <= '0;  stat_ref <= stat_ref + 1;
          end
          default: ;
        endcase
      end
    end
  end
endmodule
