// R4000-style IF/IS/RF/EX/DF/DS/TC/WB variant of the MIPS teaching core.
module r4000_superpipeline8 #(
    parameter int XLEN = 64,
    parameter bit DELAY_SLOT = 0
) (
    input  logic                clk,
    input  logic                rst_n,
    output logic [31:0]         imem_addr,
    input  logic [31:0]         imem_rdata,
    output logic [XLEN-1:0]     dmem_addr,
    output logic [XLEN-1:0]     dmem_wdata,
    output logic                dmem_we,
    input  logic [XLEN-1:0]     dmem_rdata,
    input  logic [4:0]          dbg_raddr,
    output logic [XLEN-1:0]     dbg_rdata,
    output logic                halted,
    output logic [31:0]         stat_cycles,
    output logic [31:0]         stat_retired,
    output logic [31:0]         stat_load_stalls,     // load-use
    output logic [31:0]         stat_branch_stalls,   // branch operand not ready
    output logic [31:0]         stat_flushes          // taken branches/jumps (three flushed stages without a delay slot)
);
  localparam bit IS64 = (XLEN == 64);
  localparam logic [5:0] F_ADD = IS64 ? 6'h2D : 6'h20;     // DADDU / ADD
  localparam logic [5:0] F_SUB = IS64 ? 6'h2F : 6'h22;     // DSUBU / SUB
  localparam logic [5:0] F_SLL = IS64 ? 6'h38 : 6'h00;     // DSLL  / SLL
  localparam logic [5:0] F_SRL = IS64 ? 6'h3A : 6'h02;     // DSRL  / SRL
  localparam logic [5:0] O_ADDI = IS64 ? 6'h19 : 6'h08;    // DADDIU / ADDI
  localparam logic [5:0] O_LOAD = IS64 ? 6'h37 : 6'h23;    // LD / LW
  localparam logic [5:0] O_STORE = IS64 ? 6'h3F : 6'h2B;   // SD / SW

  typedef enum logic [3:0] {A_ADD, A_SUB, A_AND, A_OR, A_XOR, A_SLT, A_SLL, A_SRL, A_PASSB} alu_t;

  // ---------------------------------------------------------------- register file
  logic [XLEN-1:0] regs [1:31];
  logic            rf_we;
  logic [4:0]      rf_waddr;
  logic [XLEN-1:0] rf_wdata;
  function automatic logic [XLEN-1:0] rf_read(input logic [4:0] a);          // write-through
    if (a == 5'd0)                   rf_read = '0;
    else if (rf_we && rf_waddr == a) rf_read = rf_wdata;
    else                             rf_read = regs[a];
  endfunction
  assign dbg_rdata = (dbg_raddr == 5'd0) ? '0 : regs[dbg_raddr];
  always_ff @(posedge clk)
    if (!rst_n) for (int i = 1; i < 32; i++) regs[i] <= '0;
    else if (rf_we && rf_waddr != 5'd0) regs[rf_waddr] <= rf_wdata;

  // ---------------------------------------------------------------- pipeline registers
  logic [31:0] pc_f;
  logic valid_is;
  logic [31:0] pc_is, instr_is;
  logic is_branch_e, is_bne_e, is_jump_e, is_jr_e;
  logic [31:0] br_target_e, j_target_e;
  logic valid_ds, reg_write_ds, mem_read_ds, is_halt_ds;
  logic [4:0] dest_ds;
  logic [XLEN-1:0] value_ds;
  logic valid_tc, reg_write_tc, is_halt_tc;
  logic [4:0] dest_tc;
  logic [XLEN-1:0] value_tc;
  logic        valid_d;  logic [31:0] pc_d, instr_d;
  logic        valid_e, reg_write_e, mem_read_e, mem_write_e, use_imm_e, is_jal_e, is_halt_e;
  alu_t        alu_op_e;
  logic [4:0]  dest_e, ra_e, rb_e;
  logic [31:0] pc4_e;
  logic [XLEN-1:0] va_e, vb_e, imm_e;
  logic        valid_m, reg_write_m, mem_read_m, mem_write_m, is_halt_m;
  logic [4:0]  dest_m;  logic [XLEN-1:0] alu_m, store_m;
  logic        valid_w, reg_write_w, is_halt_w;
  logic [4:0]  dest_w;  logic [XLEN-1:0] wb_w;

  // ---------------------------------------------------------------- ID: decode
  wire [5:0]  opcode = instr_d[31:26];
  wire [4:0]  rs     = instr_d[25:21];
  wire [4:0]  rt     = instr_d[20:16];
  wire [4:0]  rdf    = instr_d[15:11];
  wire [4:0]  shamt  = instr_d[10:6];
  wire [5:0]  funct  = instr_d[5:0];
  wire [15:0] imm16  = instr_d[15:0];
  wire [63:0] sx16   = {{48{imm16[15]}}, imm16};
  wire [63:0] zx16   = {48'b0, imm16};
  wire [63:0] lui64  = {{32{imm16[15]}}, imm16, 16'b0};

  logic reg_write_d, mem_read_d, mem_write_d, use_imm_d, is_branch_d, is_bne_d, is_j_d, is_jal_d, is_jr_d, is_halt_d;
  logic use_a_d, use_b_d;
  logic [4:0] src_a_d, src_b_d, dest_d;
  logic [XLEN-1:0] imm_d;
  alu_t alu_op_d;

  always_comb begin
    reg_write_d = 0; mem_read_d = 0; mem_write_d = 0; use_imm_d = 0; is_branch_d = 0; is_bne_d = 0;
    is_j_d = 0; is_jal_d = 0; is_jr_d = 0; is_halt_d = 0; use_a_d = 0; use_b_d = 0;
    src_a_d = rs; src_b_d = rt; dest_d = rdf; imm_d = sx16[XLEN-1:0]; alu_op_d = A_ADD;
    if (opcode == 6'h00) begin                                      // R-type
      if (funct == F_ADD)      begin reg_write_d = 1; use_a_d = 1; use_b_d = 1; alu_op_d = A_ADD; end
      else if (funct == F_SUB) begin reg_write_d = 1; use_a_d = 1; use_b_d = 1; alu_op_d = A_SUB; end
      else if (funct == 6'h24) begin reg_write_d = 1; use_a_d = 1; use_b_d = 1; alu_op_d = A_AND; end
      else if (funct == 6'h25) begin reg_write_d = 1; use_a_d = 1; use_b_d = 1; alu_op_d = A_OR;  end
      else if (funct == 6'h26) begin reg_write_d = 1; use_a_d = 1; use_b_d = 1; alu_op_d = A_XOR; end
      else if (funct == 6'h2A) begin reg_write_d = 1; use_a_d = 1; use_b_d = 1; alu_op_d = A_SLT; end
      else if (funct == F_SLL) begin reg_write_d = 1; use_a_d = 1; src_a_d = rt; use_imm_d = 1; imm_d = XLEN'(shamt); alu_op_d = A_SLL; end
      else if (funct == F_SRL) begin reg_write_d = 1; use_a_d = 1; src_a_d = rt; use_imm_d = 1; imm_d = XLEN'(shamt); alu_op_d = A_SRL; end
      else if (funct == 6'h08) begin is_jr_d = 1; use_a_d = 1; end
      else if (funct == 6'h0D) begin is_halt_d = 1; end            // BREAK
    end else if (opcode == O_ADDI) begin reg_write_d = 1; use_a_d = 1; use_imm_d = 1; dest_d = rt; alu_op_d = A_ADD;
    end else if (opcode == 6'h0C)  begin reg_write_d = 1; use_a_d = 1; use_imm_d = 1; dest_d = rt; alu_op_d = A_AND; imm_d = zx16[XLEN-1:0];
    end else if (opcode == 6'h0D)  begin reg_write_d = 1; use_a_d = 1; use_imm_d = 1; dest_d = rt; alu_op_d = A_OR;  imm_d = zx16[XLEN-1:0];
    end else if (opcode == 6'h0F)  begin reg_write_d = 1; use_imm_d = 1; dest_d = rt; alu_op_d = A_PASSB; imm_d = lui64[XLEN-1:0];
    end else if (opcode == O_LOAD) begin reg_write_d = 1; mem_read_d = 1; use_a_d = 1; use_imm_d = 1; dest_d = rt;
    end else if (opcode == O_STORE) begin mem_write_d = 1; use_a_d = 1; use_b_d = 1; use_imm_d = 1;
    end else if (opcode == 6'h04)  begin is_branch_d = 1; use_a_d = 1; use_b_d = 1;
    end else if (opcode == 6'h05)  begin is_branch_d = 1; is_bne_d = 1; use_a_d = 1; use_b_d = 1;
    end else if (opcode == 6'h02)  begin is_j_d = 1;
    end else if (opcode == 6'h03)  begin is_jal_d = 1; reg_write_d = 1; dest_d = 5'd31;
    end
  end

  // Register fetch waits until the producer can forward the load from TC.
  wire match_e=(use_a_d && src_a_d==dest_e) || (use_b_d && src_b_d==dest_e);
  wire match_df=(use_a_d && src_a_d==dest_m) || (use_b_d && src_b_d==dest_m);
  wire load_use=valid_d && ((valid_e && mem_read_e && dest_e!=0 && match_e) ||
                            (valid_m && mem_read_m && dest_m!=0 && match_df));
  wire [31:0] pc4_d=pc_d+32'd4;
  wire [31:0] br_target=pc4_d+{sx16[29:0],2'b00};
  wire [31:0] j_target={pc4_d[31:28],instr_d[25:0],2'b00};
  wire stall=load_use;

  // ---------------------------------------------------------------- EX: forwarding and ALU
  logic [XLEN-1:0] fa, fb, ob, alu_y, ex_result;
  wire branch_taken=is_bne_e ? (fa!=fb) : (fa==fb);
  wire redirect=valid_e && ((is_branch_e && branch_taken) || is_jump_e || is_jr_e);
  wire [31:0] target=is_jr_e ? fa[31:0] : is_jump_e ? j_target_e : br_target_e;
  always_comb begin
    fa = va_e;  fb = vb_e;
    if (reg_write_w && valid_w && dest_w != 0 && dest_w == ra_e) fa = wb_w;
    if (reg_write_w && valid_w && dest_w != 0 && dest_w == rb_e) fb = wb_w;
    if (reg_write_tc && valid_tc && dest_tc!=0 && dest_tc==ra_e) fa=value_tc;
    if (reg_write_tc && valid_tc && dest_tc!=0 && dest_tc==rb_e) fb=value_tc;
    if (reg_write_ds && valid_ds && !mem_read_ds && dest_ds!=0 && dest_ds==ra_e) fa=value_ds;
    if (reg_write_ds && valid_ds && !mem_read_ds && dest_ds!=0 && dest_ds==rb_e) fb=value_ds;
    if (reg_write_m && valid_m && !mem_read_m && dest_m!=0 && dest_m==ra_e) fa=alu_m;
    if (reg_write_m && valid_m && !mem_read_m && dest_m!=0 && dest_m==rb_e) fb=alu_m;
    ob = use_imm_e ? imm_e : fb;
    case (alu_op_e)
      A_ADD:   alu_y = fa + ob;
      A_SUB:   alu_y = fa - ob;
      A_AND:   alu_y = fa & ob;
      A_OR:    alu_y = fa | ob;
      A_XOR:   alu_y = fa ^ ob;
      A_SLT:   alu_y = {{(XLEN-1){1'b0}}, $signed(fa) < $signed(ob)};
      A_SLL:   alu_y = fa << ob[5:0];
      A_SRL:   alu_y = fa >> ob[5:0];
      default: alu_y = ob;                                           // A_PASSB (LUI)
    endcase
    ex_result = is_jal_e ? XLEN'(pc4_e+(DELAY_SLOT ? 4 : 0)) : alu_y;
  end

  // ---------------------------------------------------------------- MEM / WB
  assign imem_addr  = pc_f;
  assign dmem_addr  = alu_m;
  assign dmem_wdata = store_m;
  assign dmem_we    = valid_m && mem_write_m && !halted && !is_halt_ds && !is_halt_tc && !is_halt_w;
  assign rf_we      = valid_w && reg_write_w && !halted;
  assign rf_waddr   = dest_w;
  assign rf_wdata   = wb_w;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_is<=0; valid_ds<=0; valid_tc<=0;
      reg_write_ds<=0; reg_write_tc<=0; mem_read_ds<=0; is_halt_ds<=0; is_halt_tc<=0;
      is_branch_e<=0; is_bne_e<=0; is_jump_e<=0; is_jr_e<=0;
      dest_ds<=0; dest_tc<=0; value_ds<=0; value_tc<=0;
      pc_f <= 0; valid_d <= 0; valid_e <= 0; valid_m <= 0; valid_w <= 0; halted <= 0;
      reg_write_e <= 0; mem_read_e <= 0; mem_write_e <= 0; is_jal_e <= 0; is_halt_e <= 0;
      reg_write_m <= 0; mem_read_m <= 0; mem_write_m <= 0; is_halt_m <= 0; reg_write_w <= 0; is_halt_w <= 0;
      dest_e <= 0; dest_m <= 0; dest_w <= 0;
      stat_cycles <= 0; stat_retired <= 0; stat_load_stalls <= 0; stat_branch_stalls <= 0; stat_flushes <= 0;
    end else if (!halted) begin
      // IF / IS
      if (redirect) begin
        pc_f<=target; valid_is<=0;
        if (!DELAY_SLOT || !stall) valid_d<=0;
      end else if (!stall) begin
        pc_f<=pc_f+4; pc_is<=pc_f; instr_is<=imem_rdata; valid_is<=1;
        pc_d<=pc_is; instr_d<=instr_is; valid_d<=valid_is;
      end
      // ID -> EX
      if (stall || !valid_d || (redirect && !DELAY_SLOT)) begin
        is_branch_e<=0; is_bne_e<=0; is_jump_e<=0; is_jr_e<=0;
        valid_e <= 0; reg_write_e <= 0; mem_read_e <= 0; mem_write_e <= 0; is_jal_e <= 0; is_halt_e <= 0; dest_e <= 0;
      end else begin
        is_branch_e<=is_branch_d; is_bne_e<=is_bne_d;
        is_jump_e<=is_j_d||is_jal_d; is_jr_e<=is_jr_d;
        br_target_e<=br_target; j_target_e<=j_target;
        valid_e <= 1; reg_write_e <= reg_write_d; mem_read_e <= mem_read_d; mem_write_e <= mem_write_d;
        use_imm_e <= use_imm_d; is_jal_e <= is_jal_d; is_halt_e <= is_halt_d; alu_op_e <= alu_op_d;
        dest_e <= dest_d; ra_e <= use_a_d ? src_a_d : 5'd0; rb_e <= use_b_d ? src_b_d : 5'd0;
        pc4_e <= pc4_d; imm_e <= imm_d; va_e <= rf_read(src_a_d); vb_e <= rf_read(src_b_d);
      end
      // EX -> MEM
      valid_m <= valid_e; reg_write_m <= reg_write_e; mem_read_m <= mem_read_e; mem_write_m <= mem_write_e;
      is_halt_m <= is_halt_e; dest_m <= dest_e; alu_m <= ex_result; store_m <= fb;
      // DF -> DS samples memory; DS -> TC exposes checked load data.
      valid_ds<=valid_m; reg_write_ds<=reg_write_m; is_halt_ds<=is_halt_m;
      mem_read_ds<=mem_read_m; dest_ds<=dest_m;
      value_ds<=mem_read_m ? dmem_rdata : alu_m;
      valid_tc<=valid_ds; reg_write_tc<=reg_write_ds; is_halt_tc<=is_halt_ds;
      dest_tc<=dest_ds; value_tc<=value_ds;
      // TC -> WB
      valid_w<=valid_tc; reg_write_w<=reg_write_tc; is_halt_w<=is_halt_tc;
      dest_w<=dest_tc; wb_w<=value_tc;
      // statistics / halt
      if (valid_w && is_halt_w) halted <= 1;
      if (!halted) begin
        stat_cycles <= stat_cycles + 1;
        if (valid_w)   stat_retired <= stat_retired + 1;
        if (load_use && (!redirect || DELAY_SLOT)) stat_load_stalls   <= stat_load_stalls + 1;

        if (redirect) stat_flushes<=stat_flushes+(DELAY_SLOT ? 2 : 3);
      end
    end
  end
endmodule
