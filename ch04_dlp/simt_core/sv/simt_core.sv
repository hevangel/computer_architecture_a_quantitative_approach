// A small GPU-style SIMT core (Chapter 4): NW warps of WS lanes sharing one instruction stream per warp.
//
//   * Each cycle a round-robin scheduler picks one READY warp and issues one instruction for all of its ACTIVE lanes at once.
//   * Fixed-latency mode stalls the warp on a load. Async mode tracks pending destinations per warp,
//     allowing overlapping loads and independent instructions while protecting their destinations from read/write hazards.
//   * Branch divergence uses a per-warp reconvergence stack (as in NVIDIA's SSY/SYNC scheme):
//        SSY            push {mask = current active mask}                        (marks a reconvergence region)
//        BEQZ ra, T     lanes with ra == 0 want pc = T, the others fall through.  If both groups exist the warp DIVERGES:
//                       push {pc = T, mask = taken lanes} and continue with the not-taken lanes.
//        SYNC           pop: a pending path -> run it (pc = its pc, mask = its mask); an SSY token -> restore its mask, pc + 1
//   * Lanes run with the active mask; masked-off lanes do nothing.  Lane utilisation = lane_ops / (issued * WS).
//
// Instruction word: [31:27] op | [26:23] rd | [22:19] ra | [18:15] rb | [14:0] imm (sign-extended); registers r0..r7 per lane, r0 = 0.
//   0 NOP | 1 ADD | 2 SUB | 3 MUL | 5 ANDI rd=ra&imm | 6 ADDI rd=ra+imm | 7 TID rd=global thread id | 8 LD rd=mem[ra+imm]
//   9 ST mem[ra+imm]=rb | 10 BEQZ ra,imm | 11 BRA imm | 12 SSY | 13 SYNC | 14 EXIT.
//   Async-only: 15 shared LD | 16 shared ST | 17 full-block barrier. Memory is word addressed, one port per lane.
module simt_core #(
    parameter int NW     = 4,
    parameter int WS     = 8,
    parameter int LD_LAT = 6,          // >= 2
    parameter bit ASYNC_MEM = 0,       // use tagged request/response memory
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
    output logic [31:0]          stat_idle,         // cycles with no warp ready
    output logic                 mem_req_valid,
    input  logic                 mem_req_ready,
    output logic                 mem_req_write,
    output logic                 mem_req_shared,
    output logic [7:0]           mem_req_warp,
    output logic [2:0]           mem_req_rd,
    output logic [WS-1:0]        mem_req_mask,
    input  logic                 mem_resp_valid,
    input  logic [7:0]           mem_resp_warp,
    input  logic [2:0]           mem_resp_rd,
    input  logic [WS*32-1:0]     mem_resp_rdata
);
  localparam int NREG = 8;
  localparam int WIDX = (NW > 1) ? $clog2(NW) : 1;

  logic [7:0]    pc     [0:NW-1];
  logic [WS-1:0] mask   [0:NW-1];
  logic          done   [0:NW-1];
  logic [7:0]    waitc  [0:NW-1];
  logic [NW-1:0] barrier_waiting;
  logic [3:0]    sp     [0:NW-1];
  logic [7:0]    st_pc   [0:NW*DEPTH-1];
  logic [WS-1:0] st_mask [0:NW*DEPTH-1];
  logic          st_kind [0:NW*DEPTH-1];                  // 0 = pending path, 1 = SSY token
  logic [31:0]   regs    [0:NW*WS*NREG-1];
  logic [31:0]   ld_data [0:NW*WS-1];
  logic [3:0]    ld_rd   [0:NW-1];
  logic [WS-1:0] ld_mask [0:NW-1];
  logic [7:0] pending [0:NW-1];
  logic [WS-1:0] pending_mask [0:NW*NREG-1];
  logic [WIDX-1:0] rr;
  logic hold_valid; logic [WIDX-1:0] hold_sel;

  // ---- scheduler -------------------------------------------------------------------------------------
  logic [WIDX-1:0] sel;  logic found;
  always_comb begin
    found = 1'b0;  sel = '0;
    for (int k = 1; k <= NW; k++) begin
      int w;  w = (int'(rr) + k) % NW;
      if (!found && !done[w] && !barrier_waiting[w] && (ASYNC_MEM || waitc[w] == 8'd0)) begin found = 1'b1; sel = WIDX'(w); end
    end
    if (ASYNC_MEM && hold_valid) begin found=1; sel=hold_sel; end
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
      dmem_we[l] = !ASYNC_MEM && found && !all_done && (op == 5'd9) && amask[l];
    end
  end

  // Loads have destination tags; stores and zero-register loads use tag zero.
  // Stores wait for earlier memory operations and block later ones.
  logic hazard, use_a, use_b, write_rd;
  always_comb begin
    use_a = (op==1 || op==2 || op==3 || op==5 || op==6 || op==8 || op==9 || op==10 || op==15 || op==16);
    use_b = (op==1 || op==2 || op==3 || op==9 || op==16);
    write_rd = (op==1 || op==2 || op==3 || op==5 || op==6 || op==7 || op==8 || op==15);
    hazard = 1'b0;
    if (ASYNC_MEM) begin
      if (use_a && ran[2:0]!=0 && pending[sel][ran[2:0]]) hazard=1'b1;
      if (use_b && rbn[2:0]!=0 && pending[sel][rbn[2:0]]) hazard=1'b1;
      if (write_rd && rdn[2:0]!=0 && pending[sel][rdn[2:0]]) hazard=1'b1;
      if ((op==8 || op==15) && (pending[sel][0] || pending[sel][rdn[2:0]])) hazard=1'b1;
      if ((op==9 || op==16 || op==14 || op==17) && pending[sel]!=0) hazard=1'b1;
    end
  end
  assign mem_req_valid = ASYNC_MEM && found && !all_done && !hazard && (op==5'd8 || op==5'd9 || op==5'd15 || op==5'd16);
  assign mem_req_write = (op==5'd9 || op==5'd16);
  assign mem_req_shared = (op==5'd15 || op==5'd16);
  assign mem_req_warp = 8'(sel);
  assign mem_req_rd = mem_req_write ? 3'd0 : rdn[2:0];
  assign mem_req_mask = amask;

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
      rr <= WIDX'(NW - 1); hold_valid<=0; hold_sel<=0; barrier_waiting<='0;
      stat_cycles <= '0; stat_issued <= '0; stat_lane_ops <= '0; stat_idle <= '0;
      for (int w = 0; w < NW; w++) begin
        pc[w] <= '0; mask[w] <= '1; done[w] <= 1'b0; waitc[w] <= '0; sp[w] <= '0; ld_rd[w] <= '0; ld_mask[w] <= '0; pending[w] <= '0;
      end
      for (int i = 0; i < NW*DEPTH; i++) begin st_pc[i] <= '0; st_mask[i] <= '0; st_kind[i] <= 1'b0; end
      for (int i = 0; i < NW*WS*NREG; i++) regs[i] <= '0;
      for (int i = 0; i < NW*WS; i++) ld_data[i] <= '0;
      for (int i = 0; i < NW*NREG; i++) pending_mask[i] <= '0;
    end else if (!all_d) begin
      stat_cycles <= stat_cycles + 1;
      if (ASYNC_MEM) begin
        if (mem_req_valid && !mem_req_ready) begin hold_valid<=1; hold_sel<=sel; end
        else if (mem_req_valid && mem_req_ready) hold_valid<=0;
        if (mem_resp_valid && int'(mem_resp_warp)<NW && pending[mem_resp_warp][mem_resp_rd]) begin
          pending[mem_resp_warp][mem_resp_rd]<=0;
          for (int l=0;l<WS;l++)
            if (pending_mask[int'(mem_resp_warp)*NREG+int'(mem_resp_rd)][l] && mem_resp_rd!=0)
              regs[(int'(mem_resp_warp)*WS+l)*NREG+int'(mem_resp_rd)]<=mem_resp_rdata[32*l+:32];
        end
      end else begin
        for (int w=0;w<NW;w++)
          if (waitc[w]!=0) begin
            waitc[w]<=waitc[w]-1;
            if(waitc[w]==1)
              for(int l=0;l<WS;l++)
                if(ld_mask[w][l] && ld_rd[w][2:0]!=0) regs[(w*WS+l)*NREG+int'(ld_rd[w][2:0])]<=ld_data[w*WS+l];
          end
      end
      if (!found || hazard || (ASYNC_MEM && mem_req_valid && !mem_req_ready)) begin
        stat_idle <= stat_idle + 1;
        if (found && hazard) rr <= sel;
      end
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
          5'd8, 5'd15: begin                                                    // load: data captured now, registers written LD_LAT-1 edges later
            if (ASYNC_MEM) begin pending[sel][rdn[2:0]]<=1; pending_mask[int'(sel)*NREG+int'(rdn[2:0])]<=amask; end
            else begin
              for (int l = 0; l < WS; l++) ld_data[int'(sel)*WS + l] <= dmem_rdata[32*l +: 32];
              ld_rd[sel] <= rdn; ld_mask[sel] <= amask; waitc[sel] <= 8'(LD_LAT - 1);
            end
          end
          5'd9, 5'd16: if (ASYNC_MEM) begin pending[sel][0]<=1; pending_mask[int'(sel)*NREG]<=0; end
          5'd17: if (ASYNC_MEM) begin
            if ((barrier_waiting | ({{(NW-1){1'b0}},1'b1} << sel)) == {NW{1'b1}})
              barrier_waiting <= '0;
            else barrier_waiting[sel] <= 1'b1;
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
