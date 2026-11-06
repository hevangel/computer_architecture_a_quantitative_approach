// A 4-slot VLIW core with an exposed pipeline (Appendix H).
//
// Each 128-bit instruction word is a *bundle* of four independent 32-bit operations, one per functional-unit slot:
//     slot 0, slot 1 : integer ALU     ADD SUB MUL ADDI            (result visible to the NEXT bundle)
//     slot 2         : memory          LD  ST                      (a load's result is visible 2 bundles later)
//     slot 3         : control         BNEZ JMP HALT               (taken branch: no delay slots, no penalty)
// There are NO hardware interlocks or forwarding: the compiler (here: the assembly programmer) must schedule around the
// latencies.  Reading a register too early simply returns its OLD value.  All slots read the register file as it was at
// the start of the bundle, so the slots of one bundle execute in parallel (e.g. two slots can swap registers).
// An operation placed in a slot that cannot execute it is a NOP.  Two writes to one register in the same cycle are
// undefined (later slot wins here); the schedule must avoid them.
//
// Operation word:  [31:28] opcode | [27:24] rd | [23:20] ra | [19:16] rb | [15:0] imm (sign-extended)
//   0 NOP | 1 ADD rd=ra+rb | 2 SUB rd=ra-rb | 3 MUL rd=ra*rb | 4 ADDI rd=ra+imm | 5 LD rd=mem[ra+imm]
//   6 ST mem[ra+imm]=rb | 7 BNEZ if ra!=0 pc=imm | 8 JMP pc=imm | 15 HALT.   16 registers, r0 = 0, imm = absolute bundle index for branches.
// Statistics: stat_bundles (= cycles, one bundle per cycle) and stat_ops (non-NOP operations executed) give IPC.
module vliw4 (
    input  logic         clk,
    input  logic         rst_n,
    output logic [31:0]  imem_addr,          // bundle index
    input  logic [127:0] imem_rdata,
    output logic [31:0]  dmem_addr,          // byte address
    output logic [31:0]  dmem_wdata,
    output logic         dmem_we,
    input  logic [31:0]  dmem_rdata,
    input  logic [3:0]   dbg_raddr,
    output logic [31:0]  dbg_rdata,
    output logic         halted,
    output logic [31:0]  stat_bundles,
    output logic [31:0]  stat_ops
);
  logic [31:0] regs [1:15];
  function automatic logic [31:0] rd_reg(input logic [3:0] a);
    if (a == 4'd0) rd_reg = 32'd0; else rd_reg = regs[a];
  endfunction
  assign dbg_rdata = rd_reg(dbg_raddr);

  logic [31:0] pc;
  assign imem_addr = pc;

  // slot decode
  logic [31:0] s_op [0:3];
  logic [3:0]  opc  [0:3];
  logic [3:0]  rdn  [0:3];
  logic [31:0] ra_v [0:3];
  logic [31:0] rb_v [0:3];
  logic [31:0] immv [0:3];
  logic [31:0] alu_res [0:1];
  logic        alu_we  [0:1];
  logic        ld_issue, st_issue, taken, halt_now;
  logic [31:0] target;
  logic [31:0] nops;

  always_comb begin
    for (int s = 0; s < 4; s++) begin
      s_op[s] = imem_rdata[32*s +: 32];
      opc[s]  = s_op[s][31:28];
      rdn[s]  = s_op[s][27:24];
      ra_v[s] = rd_reg(s_op[s][23:20]);
      rb_v[s] = rd_reg(s_op[s][19:16]);
      immv[s] = {{16{s_op[s][15]}}, s_op[s][15:0]};
    end
    nops = 0;
    for (int s = 0; s < 2; s++) begin                       // ALU slots
      alu_we[s] = 1'b0;  alu_res[s] = 32'd0;
      case (opc[s])
        4'd1: begin alu_we[s] = 1'b1; alu_res[s] = ra_v[s] + rb_v[s]; end
        4'd2: begin alu_we[s] = 1'b1; alu_res[s] = ra_v[s] - rb_v[s]; end
        4'd3: begin alu_we[s] = 1'b1; alu_res[s] = ra_v[s] * rb_v[s]; end
        4'd4: begin alu_we[s] = 1'b1; alu_res[s] = ra_v[s] + immv[s]; end
        default: ;
      endcase
      if (alu_we[s]) nops = nops + 1;
    end
    ld_issue = (opc[2] == 4'd5);
    st_issue = (opc[2] == 4'd6);
    if (ld_issue || st_issue) nops = nops + 1;
    dmem_addr  = ra_v[2] + immv[2];
    dmem_wdata = rb_v[2];
    dmem_we    = st_issue && !halted;
    taken = 1'b0;  halt_now = 1'b0;  target = immv[3];
    if (opc[3] == 4'd7) begin taken = (ra_v[3] != 32'd0); nops = nops + 1; end
    if (opc[3] == 4'd8) begin taken = 1'b1;               nops = nops + 1; end
    if (opc[3] == 4'd15) begin halt_now = 1'b1;           nops = nops + 1; end
  end

  logic        ldq_v;                                      // the load issued in the previous bundle, in flight
  logic [3:0]  ldq_rd;
  logic [31:0] ldq_data;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc <= 0; halted <= 0; ldq_v <= 0; ldq_rd <= 0; ldq_data <= 0; stat_bundles <= 0; stat_ops <= 0;
      for (int i = 1; i < 16; i++) regs[i] <= 32'd0;
    end else if (!halted) begin
      if (ldq_v && ldq_rd != 4'd0) regs[ldq_rd] <= ldq_data;          // a load lands two bundles after it issued
      for (int s = 0; s < 2; s++)
        if (alu_we[s] && rdn[s] != 4'd0) regs[rdn[s]] <= alu_res[s];
      ldq_v <= ld_issue;  ldq_rd <= rdn[2];  ldq_data <= dmem_rdata;
      pc <= taken ? target : pc + 1;
      if (halt_now) halted <= 1'b1;
      stat_bundles <= stat_bundles + 1;
      stat_ops     <= stat_ops + nops;
    end
  end
endmodule
