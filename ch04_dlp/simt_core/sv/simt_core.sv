// A small GPU-style SIMT core (Chapter 4): NW warps of WS lanes sharing one instruction stream per warp.
//
//   * Each cycle a round-robin scheduler picks one READY warp and issues one instruction for all of its ACTIVE lanes at once.
//   * A load makes its warp ineligible: the dependent instruction can issue LD_LAT edges after the load.  Other warps run in
//     the meantime -- this is how a GPU hides memory latency (multithreading instead of caches/out-of-order).
//   * Branch divergence uses a per-warp reconvergence stack (as in NVIDIA's SSY/SYNC scheme):
//        SSY            push {mask = current active mask}                        (marks a reconvergence region)
//        BEQZ ra, T     lanes with ra == 0 want pc = T, the others fall through.  If both groups exist the warp DIVERGES:
//                       push {pc = T, mask = taken lanes} and continue with the not-taken lanes.
//        SYNC           pop: a pending path -> run it (pc = its pc, mask = its mask); an SSY token -> restore its mask, pc + 1
//   * Lanes run with the active mask; masked-off lanes do nothing.  Lane utilisation = lane_ops / (issued * WS).
//
// Instruction word: [31:27] op | [26:23] rd | [22:19] ra | [18:15] rb | [14:0] imm (sign-extended); registers r0..r7 per lane, r0 = 0.
//   0 NOP | 1 ADD | 2 SUB | 3 MUL | 5 ANDI rd=ra&imm | 6 ADDI rd=ra+imm | 7 TID rd=global thread id | 8 LD rd=mem[ra+imm]
//   9 ST mem[ra+imm]=rb | 10 BEQZ ra,imm | 11 BRA imm | 12 SSY | 13 SYNC | 14 EXIT.      Memory is word addressed, one port per lane.
module simt_core #(
    parameter int NW     = 4,
    parameter int WS     = 8,
    parameter int LD_LAT = 6,          // >= 2
    parameter int DEPTH  = 4           // divergence stack depth per warp
) (
    input  logic                 clk,
    input  logic                 rst_n,
    output logic [7:0]           imem_addr,
    input  logic [31:0]          imem_rdata,
    output logic [WS*16-1:0]     dmem_addr,         // one word address per lane
    output logic [WS*32-1:0]     dmem_wdata,
    output logic [WS-1:0]        dmem_we,
    input  logic [WS*32-1:0]     dmem_rdata,
    output logic                 all_done,
    output logic [31:0]          stat_cycles,
    output logic [31:0]          stat_issued,       // warp-instructions
    output logic [31:0]          stat_lane_ops,     // sum over issued instructions of the active-lane count
    output logic [31:0]          stat_idle          // cycles with no warp ready
);
  localparam int NREG = 8;
  localparam int WIDX = (NW > 1) ? $clog2(NW) : 1;

  logic [7:0]    pc     [0:NW-1];
  logic [WS-1:0] mask   [0:NW-1];
  logic          done   [0:NW-1];
  logic [7:0]    waitc  [0:NW-1];
  logic [3:0]    sp     [0:NW-1];
  logic [7:0]    st_pc   [0:NW*DEPTH-1];
  logic [WS-1:0] st_mask [0:NW*DEPTH-1];
  logic          st_kind [0:NW*DEPTH-1];                  // 0 = pending path, 1 = SSY token
  logic [31:0]   regs    [0:NW*WS*NREG-1];
  logic [31:0]   ld_data [0:NW*WS-1];
  logic [3:0]    ld_rd   [0:NW-1];
  logic [WS-1:0] ld_mask [0:NW-1];
  logic [WIDX-1:0] rr;

  // ---- scheduler -------------------------------------------------------------------------------------
  logic [WIDX-1:0] sel;  logic found;
  always_comb begin
    found = 1'b0;  sel = '0;
    for (int k = 1; k <= NW; k++) begin
      int w;  w = (int'(rr) + k) % NW;
      if (!found && !done[w] && waitc[w] == 8'd0) begin found = 1'b1; sel = WIDX'(w); end
    end
  end

  // ---- decode and per-lane operand fetch ----------------------------------------------------------------
  logic [31:0] instr;  logic [4:0] op;  logic [3:0] rdn, ran, rbn;  logic [31:0] imm;
  logic [31:0] a_l [0:WS-1];  logic [31:0] b_l [0:WS-1];  logic [WS-1:0] amask;
  logic [WS-1:0] zero_a;
  always_comb begin
    imem_addr = pc[sel];
    instr = imem_rdata;
    op = instr[31:27];  rdn = instr[26:23];  ran = instr[22:19];  rbn = instr[18:15];
    imm = {{17{instr[14]}}, instr[14:0]};
    amask = mask[sel];
    for (int l = 0; l < WS; l++) begin
      a_l[l] = (ran[2:0] == 3'd0) ? 32'd0 : regs[(int'(sel)*WS + l)*NREG + int'(ran[2:0])];
      b_l[l] = (rbn[2:0] == 3'd0) ? 32'd0 : regs[(int'(sel)*WS + l)*NREG + int'(rbn[2:0])];
      zero_a[l] = (a_l[l] == 32'd0);
      dmem_addr[16*l +: 16]  = 16'(a_l[l] + imm);
      dmem_wdata[32*l +: 32] = b_l[l];
      dmem_we[l] = found && !all_done && (op == 5'd9) && amask[l];
    end
  end

  logic [WS-1:0] taken, nottaken;
  logic [31:0]   nactive;
  always_comb begin
    taken = amask & zero_a;  nottaken = amask & ~zero_a;
    nactive = 32'd0;
    for (int l = 0; l < WS; l++) if (amask[l]) nactive = nactive + 32'd1;
  end

  logic all_d;
  always_comb begin
    all_d = 1'b1;
    for (int w = 0; w < NW; w++) if (!done[w]) all_d = 1'b0;
    all_done = all_d;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rr <= WIDX'(NW - 1);
      stat_cycles <= '0; stat_issued <= '0; stat_lane_ops <= '0; stat_idle <= '0;
      for (int w = 0; w < NW; w++) begin
        pc[w] <= '0; mask[w] <= '1; done[w] <= 1'b0; waitc[w] <= '0; sp[w] <= '0; ld_rd[w] <= '0; ld_mask[w] <= '0;
      end
      for (int i = 0; i < NW*DEPTH; i++) begin st_pc[i] <= '0; st_mask[i] <= '0; st_kind[i] <= 1'b0; end
      for (int i = 0; i < NW*WS*NREG; i++) regs[i] <= '0;
      for (int i = 0; i < NW*WS; i++) ld_data[i] <= '0;
    end else if (!all_d) begin
      stat_cycles <= stat_cycles + 1;
      // outstanding loads: count down, write the registers when the data "arrives"
      for (int w = 0; w < NW; w++)
        if (waitc[w] != 8'd0) begin
          waitc[w] <= waitc[w] - 8'd1;
          if (waitc[w] == 8'd1)
            for (int l = 0; l < WS; l++)
              if (ld_mask[w][l] && ld_rd[w][2:0] != 3'd0) regs[(w*WS + l)*NREG + int'(ld_rd[w][2:0])] <= ld_data[w*WS + l];
        end
      if (!found) stat_idle <= stat_idle + 1;
      else begin
        rr <= sel;
        stat_issued  <= stat_issued + 1;
        stat_lane_ops <= stat_lane_ops + nactive;
        pc[sel] <= pc[sel] + 8'd1;                                      // default; control instructions override below
        for (int l = 0; l < WS; l++) if (amask[l] && rdn[2:0] != 3'd0) begin
          case (op)
            5'd1: regs[(int'(sel)*WS + l)*NREG + int'(rdn[2:0])] <= a_l[l] + b_l[l];
            5'd2: regs[(int'(sel)*WS + l)*NREG + int'(rdn[2:0])] <= a_l[l] - b_l[l];
            5'd3: regs[(int'(sel)*WS + l)*NREG + int'(rdn[2:0])] <= a_l[l] * b_l[l];
            5'd5: regs[(int'(sel)*WS + l)*NREG + int'(rdn[2:0])] <= a_l[l] & imm;
            5'd6: regs[(int'(sel)*WS + l)*NREG + int'(rdn[2:0])] <= a_l[l] + imm;
            5'd7: regs[(int'(sel)*WS + l)*NREG + int'(rdn[2:0])] <= 32'(int'(sel)*WS + l);
            default: ;
          endcase
        end
        case (op)
          5'd8: begin                                                    // load: data captured now, registers written LD_LAT-1 edges later
            for (int l = 0; l < WS; l++) ld_data[int'(sel)*WS + l] <= dmem_rdata[32*l +: 32];
            ld_rd[sel] <= rdn;  ld_mask[sel] <= amask;  waitc[sel] <= 8'(LD_LAT - 1);
          end
          5'd10: begin                                                   // BEQZ
            if (taken == '0) ;                                           // nobody jumps: fall through
            else if (nottaken == '0) pc[sel] <= imm[7:0];                // everybody jumps
            else begin                                                   // divergence: run the fall-through lanes first
              st_pc[int'(sel)*DEPTH + int'(sp[sel])]   <= imm[7:0];
              st_mask[int'(sel)*DEPTH + int'(sp[sel])] <= taken;
              st_kind[int'(sel)*DEPTH + int'(sp[sel])] <= 1'b0;
              sp[sel] <= sp[sel] + 4'd1;
              mask[sel] <= nottaken;
            end
          end
          5'd11: pc[sel] <= imm[7:0];                                    // BRA
          5'd12: begin                                                   // SSY: remember the mask to restore at reconvergence
            st_pc[int'(sel)*DEPTH + int'(sp[sel])]   <= 8'd0;
            st_mask[int'(sel)*DEPTH + int'(sp[sel])] <= amask;
            st_kind[int'(sel)*DEPTH + int'(sp[sel])] <= 1'b1;
            sp[sel] <= sp[sel] + 4'd1;
          end
          5'd13: begin                                                   // SYNC: pop
            sp[sel] <= sp[sel] - 4'd1;
            mask[sel] <= st_mask[int'(sel)*DEPTH + int'(sp[sel]) - 1];
            if (!st_kind[int'(sel)*DEPTH + int'(sp[sel]) - 1]) pc[sel] <= st_pc[int'(sel)*DEPTH + int'(sp[sel]) - 1];
          end
          5'd14: begin done[sel] <= 1'b1; pc[sel] <= pc[sel]; end         // EXIT
          default: ;
        endcase
      end
    end
  end
endmodule
