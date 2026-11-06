library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_rv32i_pipeline is end entity;

architecture sim of tb_rv32i_pipeline is
  subtype word is std_logic_vector(31 downto 0);
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_rdata, dbg_rdata : word;
  signal dmem_we, halted : std_logic;
  signal dbg_raddr : std_logic_vector(4 downto 0) := (others => '0');
  signal cycles, retired, stalls, flushes : unsigned(31 downto 0);

  type mem_t is array (0 to 63) of word;
  signal dmem : mem_t := (others => (others => '0'));

  -- ---- tiny RV32I assembler (functions) -----------------------------------
  function reg(n : natural) return std_logic_vector is
  begin return std_logic_vector(to_unsigned(n, 5)); end function;
  function imm(n : integer; w : natural) return std_logic_vector is
  begin return std_logic_vector(to_signed(n, w)); end function;

  function r_type(f7 : std_logic_vector(6 downto 0); rs2, rs1 : natural; f3 : std_logic_vector(2 downto 0); rd : natural) return word is
  begin return f7 & reg(rs2) & reg(rs1) & f3 & reg(rd) & "0110011"; end function;
  function i_type(i : integer; rs1 : natural; f3 : std_logic_vector(2 downto 0); rd : natural; op : std_logic_vector(6 downto 0)) return word is
  begin return imm(i, 12) & reg(rs1) & f3 & reg(rd) & op; end function;

  function addi(rd, rs1 : natural; i : integer) return word is begin return i_type(i, rs1, "000", rd, "0010011"); end function;
  function add (rd, rs1, rs2 : natural) return word is begin return r_type("0000000", rs2, rs1, "000", rd); end function;
  function sub (rd, rs1, rs2 : natural) return word is begin return r_type("0100000", rs2, rs1, "000", rd); end function;
  function slt (rd, rs1, rs2 : natural) return word is begin return r_type("0000000", rs2, rs1, "010", rd); end function;
  function slli(rd, rs1 : natural; sh : integer) return word is begin return i_type(sh, rs1, "001", rd, "0010011"); end function;
  function lw  (rd : natural; off : integer; rs1 : natural) return word is begin return i_type(off, rs1, "010", rd, "0000011"); end function;
  function jalr(rd, rs1 : natural; off : integer) return word is begin return i_type(off, rs1, "000", rd, "1100111"); end function;
  function sw  (rs2 : natural; off : integer; rs1 : natural) return word is
    variable o : std_logic_vector(11 downto 0) := imm(off, 12);
  begin return o(11 downto 5) & reg(rs2) & reg(rs1) & "010" & o(4 downto 0) & "0100011"; end function;
  function b_type(rs1, rs2 : natural; off : integer; f3 : std_logic_vector(2 downto 0)) return word is
    variable o : std_logic_vector(12 downto 0) := imm(off, 13);
  begin return o(12) & o(10 downto 5) & reg(rs2) & reg(rs1) & f3 & o(4 downto 1) & o(11) & "1100011"; end function;
  function beq(rs1, rs2 : natural; off : integer) return word is begin return b_type(rs1, rs2, off, "000"); end function;
  function bne(rs1, rs2 : natural; off : integer) return word is begin return b_type(rs1, rs2, off, "001"); end function;
  function jal(rd : natural; off : integer) return word is
    variable o : std_logic_vector(20 downto 0) := imm(off, 21);
  begin return o(20) & o(10 downto 1) & o(11) & o(19 downto 12) & reg(rd) & "1101111"; end function;
  function lui(rd : natural; u : std_logic_vector(19 downto 0)) return word is begin return u & reg(rd) & "0110111"; end function;

  function program return mem_t is
    variable m : mem_t := (others => (others => '0'));
  begin
    m(0)  := addi(1, 0, 5);          -- x1 = 5
    m(1)  := addi(2, 0, 7);          -- x2 = 7
    m(2)  := add (3, 1, 2);          -- x3 = 12           (forward from MEM/WB)
    m(3)  := sub (4, 3, 1);          -- x4 = 7            (forward from EX/MEM, distance 1)
    m(4)  := sw  (3, 0, 0);          -- mem[0] = 12
    m(5)  := lw  (5, 0, 0);          -- x5 = 12
    m(6)  := add (6, 5, 5);          -- x6 = 24           (load-use: 1 stall)
    m(7)  := beq (6, 6, 8);          -- taken -> word 9   (2 flushed instructions)
    m(8)  := addi(7, 0, 99);         -- wrong path: must not execute
    m(9)  := addi(8, 0, 1);          -- x8 = 1
    m(10) := addi(10, 0, 10);        -- x10 = 10 (loop counter)
    m(11) := addi(11, 0, 0);         -- x11 = 0  (sum)
    m(12) := add (11, 11, 10);       -- loop: sum += i
    m(13) := addi(10, 10, -1);       --       i--
    m(14) := bne (10, 0, -8);        --       until i == 0   (taken 9 times)
    m(15) := sw  (11, 4, 0);         -- mem[1] = 55
    m(16) := jal (12, 8);            -- x12 = 68, jump to word 18
    m(17) := addi(13, 0, 77);        -- wrong path
    m(18) := slt (14, 0, 11);        -- x14 = (0 < 55) = 1
    m(19) := lui (15, x"12345");     -- x15 = 0x12345000
    m(20) := addi(16, 15, 16#678#);  -- x16 = 0x12345678
    m(21) := slli(17, 14, 4);        -- x17 = 16
    m(22) := jalr(18, 0, 96);        -- x18 = 92, jump to byte 96 (word 24)
    m(23) := addi(19, 0, 55);        -- wrong path
    m(24) := x"00100073";            -- ebreak
    return m;
  end function;
  constant imem : mem_t := program;
begin
  clk <= not clk after 5 ns;

  dut : entity work.rv32i_pipeline
    port map (clk, rst_n, imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_we, dmem_rdata,
              dbg_raddr, dbg_rdata, halted, cycles, retired, stalls, flushes);

  imem_rdata <= imem(to_integer(unsigned(imem_addr(7 downto 2)))) when imem_addr(31 downto 8) = x"000000" else (others => '0');
  dmem_rdata <= dmem(to_integer(unsigned(dmem_addr(7 downto 2))));
  process (clk) begin
    if rising_edge(clk) and dmem_we = '1' then dmem(to_integer(unsigned(dmem_addr(7 downto 2)))) <= dmem_wdata; end if;
  end process;

  stim : process
    variable errors : natural := 0;
    variable t : natural := 0;
    procedure check_reg(r : natural; expect : std_logic_vector(31 downto 0)) is
    begin
      dbg_raddr <= reg(r);
      wait for 1 ns;
      if dbg_rdata /= expect then
        errors := errors + 1;
        report "FAIL x" & integer'image(r) & " mismatch" severity error;
      end if;
    end procedure;
    procedure check_stat(name : string; got : unsigned; expect : natural) is
    begin
      if to_integer(got) /= expect then
        errors := errors + 1;
        report "FAIL " & name & " = " & integer'image(to_integer(got)) & ", expected " & integer'image(expect) severity error;
      end if;
    end procedure;
  begin
    wait until falling_edge(clk);  wait until falling_edge(clk);
    rst_n <= '1';
    while halted /= '1' and t < 500 loop wait until rising_edge(clk); t := t + 1; end loop;
    if halted /= '1' then errors := errors + 1; report "FAIL: program never halted" severity error; end if;
    wait until falling_edge(clk);
    check_reg(1, x"00000005");  check_reg(2, x"00000007");  check_reg(3, x"0000000C");  check_reg(4, x"00000007");
    check_reg(5, x"0000000C");  check_reg(6, x"00000018");
    check_reg(7, x"00000000");                        -- wrong-path write must be squashed
    check_reg(8, x"00000001");  check_reg(10, x"00000000");  check_reg(11, x"00000037");  check_reg(12, x"00000044");
    check_reg(13, x"00000000");                       -- wrong-path write must be squashed
    check_reg(14, x"00000001");  check_reg(15, x"12345000");  check_reg(16, x"12345678");  check_reg(17, x"00000010");
    check_reg(18, x"0000005C");  check_reg(19, x"00000000");
    if dmem(0) /= x"0000000C" or dmem(1) /= x"00000037" then errors := errors + 1; report "FAIL memory" severity error; end if;
    check_stat("retired", retired, 49);
    check_stat("load stalls", stalls, 1);
    check_stat("taken branches/jumps", flushes, 12);
    -- pipeline CPI model: cycles = instructions + 4 (fill) + load-use stalls + 2 * taken transfers
    check_stat("cycles", cycles, 49 + 4 + 1 + 2*12);
    report "cycles=" & integer'image(to_integer(cycles)) & " retired=" & integer'image(to_integer(retired));
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
