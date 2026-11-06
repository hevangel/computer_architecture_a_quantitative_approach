// Classic 5-stage RISC pipeline (IF ID EX MEM WB) for an RV32I subset:
//   add sub and or xor slt sll srl | addi andi ori xori slti slli srli | lui
//   lw sw | beq bne blt | jal jalr | ebreak (halts, for testbenches)
//
// Hazard handling (Hennessy & Patterson, Appendix C):
//   * full forwarding  EX/MEM -> EX  and  MEM/WB -> EX; register file is write-through
//   * 1-cycle stall for a load followed immediately by a consumer (load-use)
//   * branches/jumps resolve in EX: predict-not-taken, 2 wrong-path instructions flushed
// Instruction/data memories are combinational-read, 1-cycle models supplied by the testbench.
module rv32i_pipeline
  import rv32i_pkg::*;
(
    input  logic        clk,
    input  logic        rst_n,
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic        dmem_we,
    input  logic [31:0] dmem_rdata,
    input  logic [4:0]  dbg_raddr,         // debug read port on the register file
    output logic [31:0] dbg_rdata,
    output logic        halted,            // ebreak has retired
    output logic [31:0] stat_cycles,       // all stats freeze once halted
    output logic [31:0] stat_retired,
    output logic [31:0] stat_load_stalls,
    output logic [31:0] stat_flushes       // taken branches/jumps (each costs 2 cycles)
);
  // ------------------------------------------------------------------ register file
  logic [31:0] regs [1:31];
  logic        rf_we;
  logic [4:0]  rf_waddr;
  logic [31:0] rf_wdata;

  function automatic logic [31:0] rf_read(input logic [4:0] a);   // write-through read
    if (a == 5'd0)                     rf_read = 32'd0;
    else if (rf_we && rf_waddr == a)   rf_read = rf_wdata;
    else                               rf_read = regs[a];
  endfunction
  assign dbg_rdata = (dbg_raddr == 5'd0) ? 32'd0 : regs[dbg_raddr];

  always_ff @(posedge clk)
    if (!rst_n) for (int i = 1; i < 32; i++) regs[i] <= 32'd0;
    else if (rf_we && rf_waddr != 5'd0) regs[rf_waddr] <= rf_wdata;

  // ------------------------------------------------------------------ pipeline registers
  logic [31:0] pc_f;
  // IF/ID
  logic        valid_d;  logic [31:0] pc_d, instr_d;
  // ID/EX
  logic        valid_e, reg_write_e, mem_read_e, mem_write_e, alu_src_imm_e;
  logic        is_branch_e, is_jal_e, is_jalr_e, is_lui_e, is_halt_e;
  logic [2:0]  funct3_e;  alu_op_t alu_op_e;
  logic [4:0]  rd_e, rs1_e, rs2_e;
  logic [31:0] pc_e, rs1_val_e, rs2_val_e, imm_e;
  // EX/MEM
  logic        valid_m, reg_write_m, mem_read_m, mem_write_m, is_halt_m;
  logic [4:0]  rd_m;  logic [31:0] alu_m, store_m;
  // MEM/WB
  logic        valid_w, reg_write_w, is_halt_w;
  logic [4:0]  rd_w;  logic [31:0] wb_w;

  // ------------------------------------------------------------------ ID: decode
  wire [6:0] opcode = instr_d[6:0];
  wire [4:0] rd_d   = instr_d[11:7];
  wire [2:0] f3_d   = instr_d[14:12];
  wire [4:0] rs1_d  = instr_d[19:15];
  wire [4:0] rs2_d  = instr_d[24:20];
  wire [31:0] imm_i = {{20{instr_d[31]}}, instr_d[31:20]};
  wire [31:0] imm_s = {{20{instr_d[31]}}, instr_d[31:25], instr_d[11:7]};
  wire [31:0] imm_b = {{19{instr_d[31]}}, instr_d[31], instr_d[7], instr_d[30:25], instr_d[11:8], 1'b0};
  wire [31:0] imm_u = {instr_d[31:12], 12'b0};
  wire [31:0] imm_j = {{11{instr_d[31]}}, instr_d[31], instr_d[19:12], instr_d[20], instr_d[30:21], 1'b0};

  logic reg_write_d, mem_read_d, mem_write_d, alu_src_imm_d, is_branch_d, is_jal_d, is_jalr_d, is_lui_d, is_halt_d;
  logic uses_rs1_d, uses_rs2_d;
  logic [31:0] imm_d;
  alu_op_t alu_op_d;

  function automatic alu_op_t alu_decode(input logic [2:0] f3, input logic is_sub);
    case (f3)
      3'b000:  begin if (is_sub) alu_decode = ALU_SUB; else alu_decode = ALU_ADD; end
      3'b001:  alu_decode = ALU_SLL;
      3'b010:  alu_decode = ALU_SLT;
      3'b100:  alu_decode = ALU_XOR;
      3'b101:  alu_decode = ALU_SRL;
      3'b110:  alu_decode = ALU_OR;
      3'b111:  alu_decode = ALU_AND;
      default: alu_decode = ALU_ADD;
    endcase
  endfunction

  always_comb begin
    reg_write_d = 0; mem_read_d = 0; mem_write_d = 0; alu_src_imm_d = 0; is_branch_d = 0;
    is_jal_d = 0; is_jalr_d = 0; is_lui_d = 0; is_halt_d = 0; uses_rs1_d = 1; uses_rs2_d = 0;
    imm_d = imm_i; alu_op_d = ALU_ADD;
    case (opcode)
      OP_REG:    begin reg_write_d = 1; uses_rs2_d = 1; alu_op_d = alu_decode(f3_d, instr_d[30]); end
      OP_IMM:    begin reg_write_d = 1; alu_src_imm_d = 1; alu_op_d = alu_decode(f3_d, 1'b0); end
      OP_LOAD:   begin reg_write_d = 1; mem_read_d = 1; alu_src_imm_d = 1; end
      OP_STORE:  begin mem_write_d = 1; alu_src_imm_d = 1; imm_d = imm_s; uses_rs2_d = 1; end
      OP_BRANCH: begin is_branch_d = 1; imm_d = imm_b; uses_rs2_d = 1; end
      OP_JAL:    begin reg_write_d = 1; is_jal_d = 1; imm_d = imm_j; uses_rs1_d = 0; end
      OP_JALR:   begin reg_write_d = 1; is_jalr_d = 1; alu_src_imm_d = 1; end
      OP_LUI:    begin reg_write_d = 1; is_lui_d = 1; imm_d = imm_u; uses_rs1_d = 0; end
      default:   begin uses_rs1_d = 0; if (instr_d == INSN_EBREAK) is_halt_d = 1; end
    endcase
  end

  // ------------------------------------------------------------------ EX: forward, ALU, branch
  logic [31:0] fwd_a, fwd_b, alu_b, alu_y, ex_result, br_target;
  always_comb begin
    fwd_a = rs1_val_e;  fwd_b = rs2_val_e;
    if (reg_write_w && valid_w && rd_w != 0 && rd_w == rs1_e) fwd_a = wb_w;   // older first ...
    if (reg_write_w && valid_w && rd_w != 0 && rd_w == rs2_e) fwd_b = wb_w;
    if (reg_write_m && valid_m && rd_m != 0 && rd_m == rs1_e) fwd_a = alu_m;  // ... newer overrides
    if (reg_write_m && valid_m && rd_m != 0 && rd_m == rs2_e) fwd_b = alu_m;
    alu_b = alu_src_imm_e ? imm_e : fwd_b;
    case (alu_op_e)
      ALU_ADD: alu_y = fwd_a + alu_b;
      ALU_SUB: alu_y = fwd_a - alu_b;
      ALU_AND: alu_y = fwd_a & alu_b;
      ALU_OR:  alu_y = fwd_a | alu_b;
      ALU_XOR: alu_y = fwd_a ^ alu_b;
      ALU_SLT: alu_y = {31'b0, $signed(fwd_a) < $signed(alu_b)};
      ALU_SLL: alu_y = fwd_a << alu_b[4:0];
      ALU_SRL: alu_y = fwd_a >> alu_b[4:0];
      default: alu_y = 32'd0;
    endcase
    ex_result = (is_jal_e || is_jalr_e) ? pc_e + 32'd4 : is_lui_e ? imm_e : alu_y;
  end

  logic take_branch;
  always_comb begin
    case (funct3_e)
      3'b000:  take_branch = (fwd_a == fwd_b);
      3'b001:  take_branch = (fwd_a != fwd_b);
      3'b100:  take_branch = ($signed(fwd_a) < $signed(fwd_b));
      default: take_branch = 1'b0;
    endcase
  end
  wire redirect = valid_e && ((is_branch_e && take_branch) || is_jal_e || is_jalr_e);
  assign br_target = is_jalr_e ? ((fwd_a + imm_e) & ~32'd1) : (pc_e + imm_e);

  // ------------------------------------------------------------------ hazard detection
  wire load_use = valid_d && valid_e && mem_read_e && rd_e != 0 &&
                  ((uses_rs1_d && rs1_d == rd_e) || (uses_rs2_d && rs2_d == rd_e));

  // ------------------------------------------------------------------ MEM / WB
  assign dmem_addr  = alu_m;
  assign dmem_wdata = store_m;
  assign dmem_we    = valid_m && mem_write_m;
  assign imem_addr  = pc_f;
  wire [31:0] wb_m  = mem_read_m ? dmem_rdata : alu_m;

  assign rf_we    = valid_w && reg_write_w && !halted;
  assign rf_waddr = rd_w;
  assign rf_wdata = wb_w;

  // ------------------------------------------------------------------ sequential logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_f <= 0; valid_d <= 0; valid_e <= 0; valid_m <= 0; valid_w <= 0; halted <= 0;
      reg_write_e <= 0; mem_read_e <= 0; mem_write_e <= 0; is_branch_e <= 0; is_jal_e <= 0;
      is_jalr_e <= 0; is_lui_e <= 0; is_halt_e <= 0;
      reg_write_m <= 0; mem_read_m <= 0; mem_write_m <= 0; is_halt_m <= 0;
      reg_write_w <= 0; is_halt_w <= 0;
      stat_cycles <= 0; stat_retired <= 0; stat_load_stalls <= 0; stat_flushes <= 0;
    end else begin
      // IF
      if (redirect)        begin pc_f <= br_target; valid_d <= 0; end
      else if (!load_use)  begin pc_f <= pc_f + 4; pc_d <= pc_f; instr_d <= imem_rdata; valid_d <= 1; end
      // ID -> EX (insert a bubble on stall/flush)
      if (redirect || load_use || !valid_d) begin
        valid_e <= 0; reg_write_e <= 0; mem_read_e <= 0; mem_write_e <= 0; is_branch_e <= 0;
        is_jal_e <= 0; is_jalr_e <= 0; is_lui_e <= 0; is_halt_e <= 0;
      end else begin
        valid_e <= 1; reg_write_e <= reg_write_d; mem_read_e <= mem_read_d; mem_write_e <= mem_write_d;
        alu_src_imm_e <= alu_src_imm_d; is_branch_e <= is_branch_d; is_jal_e <= is_jal_d;
        is_jalr_e <= is_jalr_d; is_lui_e <= is_lui_d; is_halt_e <= is_halt_d; alu_op_e <= alu_op_d;
        funct3_e <= f3_d; rd_e <= rd_d; rs1_e <= rs1_d; rs2_e <= rs2_d; pc_e <= pc_d; imm_e <= imm_d;
        rs1_val_e <= rf_read(rs1_d); rs2_val_e <= rf_read(rs2_d);
      end
      // EX -> MEM
      valid_m <= valid_e; reg_write_m <= reg_write_e; mem_read_m <= mem_read_e;
      mem_write_m <= mem_write_e; is_halt_m <= is_halt_e; rd_m <= rd_e;
      alu_m <= ex_result; store_m <= fwd_b;
      // MEM -> WB
      valid_w <= valid_m; reg_write_w <= reg_write_m; is_halt_w <= is_halt_m; rd_w <= rd_m; wb_w <= wb_m;
      // statistics / halt
      if (valid_w && is_halt_w) halted <= 1;
      if (!halted) begin
        stat_cycles <= stat_cycles + 1;
        if (valid_w)  stat_retired     <= stat_retired + 1;
        if (load_use) stat_load_stalls <= stat_load_stalls + 1;
        if (redirect) stat_flushes     <= stat_flushes + 1;
      end
    end
  end
endmodule
