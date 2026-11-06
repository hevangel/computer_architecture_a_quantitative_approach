-- RV32I subset used by the pipeline examples (6th/7th edition ISA).
library ieee;
use ieee.std_logic_1164.all;

package rv32i_pkg is
  constant OP_LUI    : std_logic_vector(6 downto 0) := "0110111";
  constant OP_JAL    : std_logic_vector(6 downto 0) := "1101111";
  constant OP_JALR   : std_logic_vector(6 downto 0) := "1100111";
  constant OP_BRANCH : std_logic_vector(6 downto 0) := "1100011";
  constant OP_LOAD   : std_logic_vector(6 downto 0) := "0000011";
  constant OP_STORE  : std_logic_vector(6 downto 0) := "0100011";
  constant OP_IMM    : std_logic_vector(6 downto 0) := "0010011";
  constant OP_REG    : std_logic_vector(6 downto 0) := "0110011";
  constant INSN_EBREAK : std_logic_vector(31 downto 0) := x"00100073";

  type alu_op_t is (ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR, ALU_SLT, ALU_SLL, ALU_SRL);
end package;
