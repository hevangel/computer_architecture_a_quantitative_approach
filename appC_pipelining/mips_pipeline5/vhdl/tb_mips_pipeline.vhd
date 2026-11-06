-- One harness per ISA flavor: the same logical program is assembled with DLX/MIPS32 encodings (XLEN=32)
-- and with MIPS64 encodings (XLEN=64), run to BREAK, and checked against hand-derived results.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mips_harness is
  generic (XLEN : positive := 32);
  port (clk, rst_n : in std_logic; done : out std_logic; errors : out integer);
end entity;

architecture sim of mips_harness is
  constant IS64   : boolean := (XLEN = 64);
  constant WBYTES : positive := XLEN / 8;                  -- bytes per data word
  subtype word is std_logic_vector(XLEN-1 downto 0);
  subtype w32 is std_logic_vector(31 downto 0);
  subtype reg5 is std_logic_vector(4 downto 0);
  type imem_t is array (0 to 63) of w32;
  type dmem_t is array (0 to 63) of word;

  -- ---- assembler (functions) ------------------------------------------------------------------
  function r5(n : natural) return reg5 is begin return reg5(to_unsigned(n, 5)); end function;
  function s16(n : integer) return std_logic_vector is begin return std_logic_vector(to_signed(n, 16)); end function;
  function r_type(f : natural; rs, rt, rd, sh : natural) return w32 is
  begin return "000000" & r5(rs) & r5(rt) & r5(rd) & r5(sh) & std_logic_vector(to_unsigned(f, 6)); end function;
  function i_type(op : natural; rs, rt : natural; imm : std_logic_vector(15 downto 0)) return w32 is
  begin return std_logic_vector(to_unsigned(op, 6)) & r5(rs) & r5(rt) & imm; end function;
  function pick(b : boolean; x, y : natural) return natural is begin if b then return x; else return y; end if; end function;

  function add (rd, rs, rt : natural) return w32 is begin return r_type(pick(IS64, 16#2D#, 16#20#), rs, rt, rd, 0); end function;  -- DADDU / ADD
  function sub (rd, rs, rt : natural) return w32 is begin return r_type(pick(IS64, 16#2F#, 16#22#), rs, rt, rd, 0); end function;  -- DSUBU / SUB
  function slt (rd, rs, rt : natural) return w32 is begin return r_type(16#2A#, rs, rt, rd, 0); end function;
  function shl (rd, rt, sh : natural) return w32 is begin return r_type(pick(IS64, 16#38#, 16#00#), 0, rt, rd, sh); end function;   -- DSLL / SLL
  function jr  (rs : natural) return w32 is begin return r_type(16#08#, rs, 0, 0, 0); end function;
  function brk return w32 is begin return r_type(16#0D#, 0, 0, 0, 0); end function;
  function addi(rt, rs : natural; imm : integer) return w32 is begin return i_type(pick(IS64, 16#19#, 16#08#), rs, rt, s16(imm)); end function;  -- DADDIU / ADDI
  function ori (rt, rs : natural; imm : std_logic_vector(15 downto 0)) return w32 is begin return i_type(16#0D#, rs, rt, imm); end function;
  function lui (rt : natural; imm : std_logic_vector(15 downto 0)) return w32 is begin return i_type(16#0F#, 0, rt, imm); end function;
  function lw  (rt : natural; off : integer; rs : natural) return w32 is begin return i_type(pick(IS64, 16#37#, 16#23#), rs, rt, s16(off)); end function;  -- LD / LW
  function sw  (rt : natural; off : integer; rs : natural) return w32 is begin return i_type(pick(IS64, 16#3F#, 16#2B#), rs, rt, s16(off)); end function;  -- SD / SW
  function beq (rs, rt : natural; off : integer) return w32 is begin return i_type(16#04#, rs, rt, s16(off)); end function;   -- off in words from PC+4
  function bne (rs, rt : natural; off : integer) return w32 is begin return i_type(16#05#, rs, rt, s16(off)); end function;
  function jal (w : natural) return w32 is begin return "000011" & std_logic_vector(to_unsigned(w, 26)); end function;

  function program return imem_t is
    variable m : imem_t := (others => (others => '0'));
  begin
    m(0)  := addi(1, 0, 5);            -- $1 = 5
    m(1)  := addi(2, 0, 7);            -- $2 = 7
    m(2)  := add (3, 1, 2);            -- $3 = 12            forward from MEM/WB and EX/MEM
    m(3)  := sub (4, 3, 1);            -- $4 = 7
    m(4)  := sw  (3, 0, 0);            -- mem[0] = 12
    m(5)  := lw  (5, 0, 0);            -- $5 = 12
    m(6)  := add (6, 5, 5);            -- $6 = 24            load-use stall (1)
    m(7)  := beq (6, 6, 1);            -- taken -> word 9    operand produced by the instruction just ahead: branch stall (1)
    m(8)  := addi(7, 0, 99);           -- wrong path
    m(9)  := addi(8, 0, 1);            -- $8 = 1
    m(10) := addi(10, 0, 10);          -- $10 = 10
    m(11) := addi(11, 0, 0);           -- $11 = 0
    m(12) := add (11, 11, 10);         -- loop: sum += i
    m(13) := addi(10, 10, -1);         --       i--
    m(14) := bne (10, 0, -3);          --       BNEZ: branch stall every iteration (operand from the addi ahead), taken 9 times
    m(15) := sw  (11, WBYTES, 0);      -- mem[1] = 55
    m(16) := jal (18);                 -- $31 = 68, jump to word 18
    m(17) := addi(13, 0, 77);          -- wrong path
    m(18) := slt (14, 0, 11);          -- $14 = 1
    m(19) := lui (15, x"1234");        -- $15 = 0x12340000
    m(20) := ori (16, 15, x"5678");    -- $16 = 0x12345678
    m(21) := shl (17, 14, 4);          -- $17 = 16           (DSLL for MIPS64)
    m(22) := lw  (20, 0, 0);           -- $20 = 12
    m(23) := addi(21, 0, 1);           -- $21 = 1
    m(24) := beq (20, 3, 1);           -- taken -> word 26   operand is a load now in MEM: branch stall (1)
    m(25) := addi(22, 0, 1);           -- wrong path
    m(26) := addi(18, 0, 116);         -- $18 = byte address of word 29
    m(27) := jr  (18);                 -- JR: branch stall (1), taken
    m(28) := addi(19, 0, 55);          -- wrong path
    m(29) := brk;
    return m;
  end function;
  constant imem : imem_t := program;

  signal imem_addr, imem_rdata : w32;
  signal dmem_addr, dmem_wdata, dmem_rdata, dbg_rdata : word;
  signal dmem_we, halted : std_logic;
  signal dbg_raddr : reg5 := (others => '0');
  signal cycles, retired, lstalls, bstalls, flushes : unsigned(31 downto 0);
  signal dmem : dmem_t := (others => (others => '0'));
begin
  dut : entity work.mips_pipeline
    generic map (XLEN => XLEN)
    port map (clk, rst_n, imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_we, dmem_rdata,
              dbg_raddr, dbg_rdata, halted, cycles, retired, lstalls, bstalls, flushes);

  imem_rdata <= imem(to_integer(unsigned(imem_addr(7 downto 2)))) when imem_addr(31 downto 8) = x"000000" else (others => '0');
  dmem_rdata <= dmem(to_integer(unsigned(dmem_addr(8 downto 0))) / WBYTES mod 64);
  process (clk) begin
    if rising_edge(clk) and dmem_we = '1' then
      dmem(to_integer(unsigned(dmem_addr(8 downto 0))) / WBYTES mod 64) <= dmem_wdata;
    end if;
  end process;

  stim : process
    variable errs : integer := 0;
    variable t : natural := 0;
    procedure check_reg(r : natural; expect_v : std_logic_vector(63 downto 0)) is
    begin
      dbg_raddr <= r5(r);
      wait for 1 ns;
      if dbg_rdata /= std_logic_vector(resize(unsigned(expect_v), XLEN)) then
        errs := errs + 1;
        report "FAIL [XLEN=" & integer'image(XLEN) & "] register $" & integer'image(r) & " = 0x" & to_hstring(dbg_rdata) &
               ", expected 0x" & to_hstring(std_logic_vector(resize(unsigned(expect_v), XLEN))) severity error;
      end if;
    end procedure;
    procedure check_stat(name : string; got : unsigned; expect_v : natural) is
    begin
      if to_integer(got) /= expect_v then
        errs := errs + 1;
        report "FAIL [XLEN=" & integer'image(XLEN) & "] " & name & " = " & integer'image(to_integer(got)) &
               ", expected " & integer'image(expect_v) severity error;
      end if;
    end procedure;
    function v64(n : natural) return std_logic_vector is begin return std_logic_vector(to_unsigned(n, 64)); end function;
  begin
    done <= '0';  errors <= 0;
    wait until rst_n = '1';
    while halted /= '1' and t < 500 loop wait until rising_edge(clk); t := t + 1; end loop;
    if halted /= '1' then errs := errs + 1; report "FAIL: never halted" severity error; end if;
    wait until falling_edge(clk);
    check_reg(1, v64(5));  check_reg(2, v64(7));  check_reg(3, v64(12));  check_reg(4, v64(7));  check_reg(5, v64(12));  check_reg(6, v64(24));
    check_reg(7, v64(0));                                           -- wrong-path writes must be squashed
    check_reg(8, v64(1));  check_reg(10, v64(0));  check_reg(11, v64(55));  check_reg(13, v64(0));  check_reg(14, v64(1));
    check_reg(15, x"0000000012340000");  check_reg(16, x"0000000012345678");  check_reg(17, v64(16));  check_reg(18, v64(116));  check_reg(19, v64(0));
    check_reg(20, v64(12));  check_reg(21, v64(1));  check_reg(22, v64(0));  check_reg(31, v64(68));
    if dmem(0) /= std_logic_vector(to_unsigned(12, XLEN)) or dmem(1) /= std_logic_vector(to_unsigned(55, XLEN)) then
      errs := errs + 1;  report "FAIL memory" severity error;
    end if;
    check_stat("retired", retired, 53);
    check_stat("load-use stalls", lstalls, 1);
    check_stat("branch-operand stalls", bstalls, 13);      -- beq@7 (1) + bne x10 (10) + beq@24 load-in-MEM (1) + jr (1)
    check_stat("taken transfers", flushes, 13);            -- beq@7 + bne x9 + jal + beq@24 + jr
    -- cycles = instructions + 4 (fill) + load stalls + branch stalls + 1 per taken transfer
    check_stat("cycles", cycles, 53 + 4 + 1 + 13 + 13);
    report "XLEN=" & integer'image(XLEN) & ": cycles=" & integer'image(to_integer(cycles)) & " retired=" & integer'image(to_integer(retired));
    errors <= errs;  done <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_mips_pipeline is end entity;

architecture sim of tb_mips_pipeline is
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal done32, done64 : std_logic;
  signal err32, err64 : integer;
begin
  clk <= not clk after 5 ns;
  dlx    : entity work.mips_harness generic map (32) port map (clk, rst_n, done32, err32);
  mips64 : entity work.mips_harness generic map (64) port map (clk, rst_n, done64, err64);

  process
  begin
    wait until falling_edge(clk);  wait until falling_edge(clk);
    rst_n <= '1';
    wait until done32 = '1' and done64 = '1';
    wait for 1 ns;
    if err32 + err64 = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(err32 + err64) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
