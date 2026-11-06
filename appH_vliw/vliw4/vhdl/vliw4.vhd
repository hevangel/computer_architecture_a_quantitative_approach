-- A 4-slot VLIW core with an exposed pipeline (Appendix H).
--
-- Each 128-bit instruction word is a *bundle* of four independent 32-bit operations, one per functional-unit slot:
--     slot 0, slot 1 : integer ALU     ADD SUB MUL ADDI            (result visible to the NEXT bundle)
--     slot 2         : memory          LD  ST                      (a load's result is visible 2 bundles later)
--     slot 3         : control         BNEZ JMP HALT               (taken branch: no delay slots, no penalty)
-- There are NO hardware interlocks or forwarding: the compiler (here: the assembly programmer) must schedule around the
-- latencies.  Reading a register too early simply returns its OLD value.  All slots read the register file as it was at
-- the start of the bundle, so the slots of one bundle execute in parallel (e.g. two slots can swap registers).
-- An operation placed in a slot that cannot execute it is a NOP.  Two writes to one register in the same cycle are
-- undefined (later slot wins here); the schedule must avoid them.
--
-- Operation word:  (31:28) opcode | (27:24) rd | (23:20) ra | (19:16) rb | (15:0) imm (sign-extended)
--   0 NOP | 1 ADD rd=ra+rb | 2 SUB rd=ra-rb | 3 MUL rd=ra*rb | 4 ADDI rd=ra+imm | 5 LD rd=mem[ra+imm]
--   6 ST mem[ra+imm]=rb | 7 BNEZ if ra/=0 pc=imm | 8 JMP pc=imm | 15 HALT.   16 registers, r0 = 0, imm = absolute bundle index for branches.
-- Statistics: stat_bundles (= cycles, one bundle per cycle) and stat_ops (non-NOP operations executed) give IPC.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vliw4 is
  port (
    clk, rst_n    : in  std_logic;
    imem_addr     : out std_logic_vector(31 downto 0);     -- bundle index
    imem_rdata    : in  std_logic_vector(127 downto 0);
    dmem_addr     : out std_logic_vector(31 downto 0);     -- byte address
    dmem_wdata    : out std_logic_vector(31 downto 0);
    dmem_we       : out std_logic;
    dmem_rdata    : in  std_logic_vector(31 downto 0);
    dbg_raddr     : in  std_logic_vector(3 downto 0);
    dbg_rdata     : out std_logic_vector(31 downto 0);
    halted        : out std_logic;
    stat_bundles  : out unsigned(31 downto 0);
    stat_ops      : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of vliw4 is
  subtype word is std_logic_vector(31 downto 0);
  type regs_t is array (1 to 15) of word;
  signal regs : regs_t := (others => (others => '0'));
  signal pc : unsigned(31 downto 0) := (others => '0');
  signal halted_i : std_logic := '0';
  signal bundles, nops_total : unsigned(31 downto 0) := (others => '0');

  type word_pair is array (0 to 1) of word;
  type rd_pair is array (0 to 1) of std_logic_vector(3 downto 0);
  signal alu_res : word_pair;
  signal alu_we : std_logic_vector(0 to 1);
  signal alu_rd : rd_pair;
  signal ld_issue, st_issue, taken, halt_now : std_logic;
  signal target : unsigned(31 downto 0);
  signal ld_rd_now : std_logic_vector(3 downto 0);
  signal nops : natural range 0 to 8;
  signal d_addr : word;

  signal ldq_v : std_logic := '0';
  signal ldq_rd : std_logic_vector(3 downto 0) := (others => '0');
  signal ldq_data : word := (others => '0');

  -- pure: all state it reads is passed in, so process(all) callers stay sensitive to it
  function rd_reg(a : std_logic_vector(3 downto 0); rg : regs_t) return word is
  begin
    if is_x(a) or a = "0000" then return x"00000000"; else return rg(to_integer(unsigned(a))); end if;
  end function;
begin
  imem_addr    <= std_logic_vector(pc);
  halted       <= halted_i;
  stat_bundles <= bundles;
  stat_ops     <= nops_total;
  dbg_rdata    <= rd_reg(dbg_raddr, regs);

  decode : process (all)
    variable opw : word;
    variable opc : std_logic_vector(3 downto 0);
    variable a, b, immv : word;
    variable n : natural := 0;
    variable s2a, s2b, s3a : word;
    variable s2imm : word;
  begin
    n := 0;
    for s in 0 to 1 loop                                              -- ALU slots
      opw := imem_rdata(32*s + 31 downto 32*s);
      opc := opw(31 downto 28);
      a := rd_reg(opw(23 downto 20), regs);  b := rd_reg(opw(19 downto 16), regs);
      immv := std_logic_vector(resize(signed(opw(15 downto 0)), 32));
      alu_rd(s) <= opw(27 downto 24);  alu_we(s) <= '0';  alu_res(s) <= (others => '0');
      case opc is
        when x"1" => alu_we(s) <= '1'; alu_res(s) <= std_logic_vector(unsigned(a) + unsigned(b)); n := n + 1;
        when x"2" => alu_we(s) <= '1'; alu_res(s) <= std_logic_vector(unsigned(a) - unsigned(b)); n := n + 1;
        when x"3" => alu_we(s) <= '1'; alu_res(s) <= std_logic_vector(resize(unsigned(a) * unsigned(b), 32)); n := n + 1;
        when x"4" => alu_we(s) <= '1'; alu_res(s) <= std_logic_vector(unsigned(a) + unsigned(immv)); n := n + 1;
        when others => null;
      end case;
    end loop;

    opw := imem_rdata(95 downto 64);                                  -- memory slot
    opc := opw(31 downto 28);
    s2a := rd_reg(opw(23 downto 20), regs);  s2b := rd_reg(opw(19 downto 16), regs);
    s2imm := std_logic_vector(resize(signed(opw(15 downto 0)), 32));
    ld_rd_now <= opw(27 downto 24);
    d_addr <= std_logic_vector(unsigned(s2a) + unsigned(s2imm));
    dmem_wdata <= s2b;
    if opc = x"5" then ld_issue <= '1'; n := n + 1; else ld_issue <= '0'; end if;
    if opc = x"6" then st_issue <= '1'; n := n + 1; else st_issue <= '0'; end if;

    opw := imem_rdata(127 downto 96);                                 -- control slot
    opc := opw(31 downto 28);
    s3a := rd_reg(opw(23 downto 20), regs);
    target <= unsigned(resize(signed(opw(15 downto 0)), 32));
    taken <= '0';  halt_now <= '0';
    if opc = x"7" then if unsigned(s3a) /= 0 then taken <= '1'; end if; n := n + 1; end if;
    if opc = x"8" then taken <= '1'; n := n + 1; end if;
    if opc = x"F" then halt_now <= '1'; n := n + 1; end if;
    nops <= n;
  end process;

  dmem_addr <= d_addr;
  dmem_we   <= st_issue and not halted_i;

  seq : process (clk, rst_n)
  begin
    if rst_n = '0' then
      pc <= (others => '0');  halted_i <= '0';  ldq_v <= '0';  ldq_rd <= (others => '0');  ldq_data <= (others => '0');
      bundles <= (others => '0');  nops_total <= (others => '0');
      regs <= (others => (others => '0'));
    elsif rising_edge(clk) then
      if halted_i = '0' then
        if ldq_v = '1' and ldq_rd /= "0000" then regs(to_integer(unsigned(ldq_rd))) <= ldq_data; end if;   -- a load lands two bundles after it issued
        for s in 0 to 1 loop
          if alu_we(s) = '1' and alu_rd(s) /= "0000" then regs(to_integer(unsigned(alu_rd(s)))) <= alu_res(s); end if;
        end loop;
        ldq_v <= ld_issue;  ldq_rd <= ld_rd_now;  ldq_data <= dmem_rdata;
        if taken = '1' then pc <= target; else pc <= pc + 1; end if;
        if halt_now = '1' then halted_i <= '1'; end if;
        bundles    <= bundles + 1;
        nops_total <= nops_total + nops;
      end if;
    end if;
  end process;
end architecture;
