// RV32I subset used by the pipeline examples (6th/7th edition ISA).
package rv32i_pkg;
  localparam logic [6:0] OP_LUI    = 7'b0110111;
  localparam logic [6:0] OP_JAL    = 7'b1101111;
  localparam logic [6:0] OP_JALR   = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD   = 7'b0000011;
  localparam logic [6:0] OP_STORE  = 7'b0100011;
  localparam logic [6:0] OP_IMM    = 7'b0010011;
  localparam logic [6:0] OP_REG    = 7'b0110011;
  localparam logic [31:0] INSN_EBREAK = 32'h0010_0073;

  typedef enum logic [2:0] {ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR, ALU_SLT, ALU_SLL, ALU_SRL} alu_op_t;
endpackage
