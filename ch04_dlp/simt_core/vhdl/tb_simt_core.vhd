-- PROG 0 (divergent):  y[tid] = (x[tid] even) ? 3*x[tid] : x[tid] + 100,   with x[tid] = tid
--    TID LD ANDI SSY BEQZ | ADDI BRA SYNC | ADDI MUL SYNC | ST EXIT   = 13 warp-instructions per warp, 80 lane-ops (8 lanes, half masked on 6 of them)
-- PROG 1 (uniform branches): one BEQZ every lane takes and one that no lane takes; y[tid] = tid + 7.   7 warp-instructions, 56 lane-ops per warp
-- Expected cycle / idle counts come from an independent Python model of the round-robin scheduler (LD_LAT = 6):
--    PROG 0:  1 warp -> 18 cycles, 5 idle      4 warps -> 54 cycles, 2 idle  (vs 72 if the four warps ran one after another)
--    PROG 1:  1 warp ->  7 cycles, 0 idle      4 warps -> 28 cycles, 0 idle
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity simt_harness is
  generic (NW : positive := 4; PROG : natural := 0);
  port (clk, rst_n : in std_logic; done : out std_logic; errors : out integer);
end entity;

architecture sim of simt_harness is
  constant WS : positive := 8;
  subtype word is std_logic_vector(31 downto 0);
  type imem_t is array (0 to 31) of word;
  type dmem_t is array (0 to 127) of word;

  function ins(o : natural; rd, ra, rb : natural; imm : integer) return word is
  begin
    return std_logic_vector(to_unsigned(o, 5)) & std_logic_vector(to_unsigned(rd, 4)) & std_logic_vector(to_unsigned(ra, 4)) &
           std_logic_vector(to_unsigned(rb, 4)) & std_logic_vector(to_signed(imm, 15));
  end function;
  constant OP_MUL : natural := 3;   constant OP_ANDI : natural := 5;  constant OP_ADDI : natural := 6;  constant OP_TID : natural := 7;
  constant OP_LD : natural := 8;    constant OP_ST : natural := 9;    constant OP_BEQZ : natural := 10; constant OP_BRA : natural := 11;
  constant OP_SSY : natural := 12;  constant OP_SYNC : natural := 13; constant OP_EXIT : natural := 14;

  function program return imem_t is
    variable m : imem_t := (others => (others => '0'));
  begin
    if PROG = 0 then
      m(0)  := ins(OP_TID,  1, 0, 0, 0);
      m(1)  := ins(OP_LD,   2, 1, 0, 0);          -- r2 = x[tid]
      m(2)  := ins(OP_ANDI, 3, 2, 0, 1);          -- r3 = r2 & 1
      m(3)  := ins(OP_SSY,  0, 0, 0, 0);
      m(4)  := ins(OP_BEQZ, 0, 3, 0, 7);          -- even lanes (r3 == 0) go to 7, odd lanes fall through
      m(5)  := ins(OP_ADDI, 4, 2, 0, 100);        -- odd path:  y = x + 100
      m(6)  := ins(OP_BRA,  0, 0, 0, 9);
      m(7)  := ins(OP_ADDI, 5, 0, 0, 3);          -- even path: y = 3 * x
      m(8)  := ins(OP_MUL,  4, 2, 5, 0);
      m(9)  := ins(OP_SYNC, 0, 0, 0, 0);          -- reconvergence point
      m(10) := ins(OP_ST,   0, 1, 4, 64);         -- y[tid] = r4
      m(11) := ins(OP_EXIT, 0, 0, 0, 0);
    else
      m(0)  := ins(OP_TID,  1, 0, 0, 0);
      m(1)  := ins(OP_BEQZ, 0, 6, 0, 4);          -- r6 == 0 in every lane: uniform jump to 4
      m(2)  := ins(OP_ADDI, 1, 1, 0, 1000);       -- skipped
      m(3)  := ins(OP_ADDI, 1, 1, 0, 1000);       -- skipped
      m(4)  := ins(OP_ADDI, 7, 0, 0, 1);          -- r7 = 1 in every lane
      m(5)  := ins(OP_BEQZ, 0, 7, 0, 8);          -- r7 /= 0 in every lane: uniform fall-through
      m(6)  := ins(OP_ADDI, 2, 1, 0, 7);
      m(7)  := ins(OP_ST,   0, 1, 2, 64);         -- y[tid] = tid + 7
      m(8)  := ins(OP_EXIT, 0, 0, 0, 0);
    end if;
    return m;
  end function;
  constant imem : imem_t := program;

  function init_dmem return dmem_t is
    variable d : dmem_t := (others => (others => '0'));
  begin
    for t in 0 to 31 loop d(t) := std_logic_vector(to_unsigned(t, 32)); end loop;     -- x[tid] = tid at words 0..31, y at 64..95
    return d;
  end function;

  signal imem_addr : std_logic_vector(7 downto 0);
  signal imem_rdata : word;
  signal dmem_addr : std_logic_vector(WS*16-1 downto 0);
  signal dmem_wdata, dmem_rdata : std_logic_vector(WS*32-1 downto 0);
  signal dmem_we : std_logic_vector(WS-1 downto 0);
  signal all_done : std_logic;
  signal cycles, issued, lane_ops, idle : unsigned(31 downto 0);
  signal dmem : dmem_t := init_dmem;
begin
  dut : entity work.simt_core generic map (NW => NW, WS => WS, LD_LAT => 6)
    port map (clk, rst_n, imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_we, dmem_rdata, all_done, cycles, issued, lane_ops, idle);

  imem_rdata <= imem(to_integer(unsigned(imem_addr(4 downto 0))));
  rd_ports : process (all)
  begin
    for l in 0 to WS-1 loop
      dmem_rdata(32*l + 31 downto 32*l) <= dmem(to_integer(unsigned(dmem_addr(16*l + 6 downto 16*l))));
    end loop;
  end process;
  wr_ports : process (clk)
  begin
    if rising_edge(clk) then
      for l in 0 to WS-1 loop
        if dmem_we(l) = '1' then dmem(to_integer(unsigned(dmem_addr(16*l + 6 downto 16*l)))) <= dmem_wdata(32*l + 31 downto 32*l); end if;
      end loop;
    end if;
  end process;

  stim : process
    variable errs : integer := 0;
    variable t : natural := 0;
    variable exp_y, exp_cycles, exp_idle, exp_issued, exp_ops : integer;
    procedure check_stat(name : string; got : unsigned; expect_v : integer) is
    begin
      if to_integer(got) /= expect_v then
        errs := errs + 1;
        report "FAIL [NW=" & integer'image(NW) & " PROG=" & integer'image(PROG) & "] " & name & " = " &
               integer'image(to_integer(got)) & ", expected " & integer'image(expect_v) severity error;
      end if;
    end procedure;
  begin
    done <= '0';  errors <= 0;
    wait until rst_n = '1';
    while all_done /= '1' and t < 1000 loop wait until rising_edge(clk); t := t + 1; end loop;
    if all_done /= '1' then errs := errs + 1; report "FAIL: never finished" severity error; end if;
    wait until falling_edge(clk);
    for tid in 0 to NW * WS - 1 loop
      if PROG = 0 then
        if tid mod 2 = 0 then exp_y := 3 * tid; else exp_y := tid + 100; end if;
      else exp_y := tid + 7;
      end if;
      if to_integer(unsigned(dmem(64 + tid))) /= exp_y then
        errs := errs + 1;  report "FAIL [NW=" & integer'image(NW) & " PROG=" & integer'image(PROG) & "] y[" & integer'image(tid) & "]" severity error;
      end if;
    end loop;
    if PROG = 0 then
      if NW = 1 then exp_cycles := 18; exp_idle := 5; else exp_cycles := 54; exp_idle := 2; end if;
      exp_issued := 13 * NW;  exp_ops := 80 * NW;
    else
      exp_cycles := 7 * NW;  exp_idle := 0;  exp_issued := 7 * NW;  exp_ops := 56 * NW;
    end if;
    check_stat("cycles", cycles, exp_cycles);  check_stat("idle cycles", idle, exp_idle);
    check_stat("warp-instructions", issued, exp_issued);  check_stat("lane-ops", lane_ops, exp_ops);
    report "NW=" & integer'image(NW) & " PROG=" & integer'image(PROG) & ": " & integer'image(to_integer(cycles)) & " cycles (" &
           integer'image(to_integer(idle)) & " idle), " & integer'image(to_integer(issued)) & " warp-instr";
    errors <= errs;  done <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_simt_core is end entity;

architecture sim of tb_simt_core is
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal d : std_logic_vector(3 downto 0);
  type int4 is array (0 to 3) of integer;
  signal er : int4;
begin
  clk <= not clk after 5 ns;
  h0 : entity work.simt_harness generic map (1, 0) port map (clk, rst_n, d(0), er(0));
  h1 : entity work.simt_harness generic map (4, 0) port map (clk, rst_n, d(1), er(1));
  h2 : entity work.simt_harness generic map (1, 1) port map (clk, rst_n, d(2), er(2));
  h3 : entity work.simt_harness generic map (4, 1) port map (clk, rst_n, d(3), er(3));

  process
  begin
    wait until falling_edge(clk);  wait until falling_edge(clk);
    rst_n <= '1';
    wait until d = "1111";
    wait for 1 ns;
    if er(0) + er(1) + er(2) + er(3) = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(er(0) + er(1) + er(2) + er(3)) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
