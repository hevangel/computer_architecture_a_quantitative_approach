-- The same kernel, y[i] = a*x[i] + y[i] for 8 elements (a = 3, x[i] = i+1, y[i] = 100 i), scheduled three ways:
--   PROG 0: one operation per bundle (what a scalar machine would do)               -> 75 bundles, 76 ops
--   PROG 1: operations packed into bundles within one iteration                      -> 43 bundles, 76 ops
--   PROG 2: loop unrolled x2 and re-scheduled to fill the slots                      -> 31 bundles, 60 ops
--   PROG 3: exposed-latency demonstration (reads a register before a load lands)     ->  6 bundles,  7 ops
-- Expected y[i] = 103 i + 3.  Bundle and op counts are derived by hand from the schedules.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vliw_harness is
  generic (PROG : natural := 0);
  port (clk, rst_n : in std_logic; done : out std_logic; errors : out integer);
end entity;

architecture sim of vliw_harness is
  subtype word is std_logic_vector(31 downto 0);
  subtype bnd is std_logic_vector(127 downto 0);
  type imem_t is array (0 to 63) of bnd;
  type dmem_t is array (0 to 63) of word;

  -- ---- assembler (functions) ------------------------------------------------------------------
  function r4(n : natural) return std_logic_vector is begin return std_logic_vector(to_unsigned(n, 4)); end function;
  function op(o, rd, ra, rb : natural; imm : integer) return word is
  begin return r4(o) & r4(rd) & r4(ra) & r4(rb) & std_logic_vector(to_signed(imm, 16)); end function;
  constant NOP : word := x"00000000";
  function add (rd, ra, rb : natural) return word is begin return op(1, rd, ra, rb, 0); end function;
  function mul (rd, ra, rb : natural) return word is begin return op(3, rd, ra, rb, 0); end function;
  function addi(rd, ra : natural; i : integer) return word is begin return op(4, rd, ra, 0, i); end function;
  function ld  (rd, ra : natural; i : integer) return word is begin return op(5, rd, ra, 0, i); end function;
  function st  (ra : natural; i : integer; rb : natural) return word is begin return op(6, 0, ra, rb, i); end function;
  function bnez(ra : natural; target : integer) return word is begin return op(7, 0, ra, 0, target); end function;
  function halt return word is begin return op(15, 0, 0, 0, 0); end function;
  function bundle(s0, s1, s2, s3 : word) return bnd is begin return s3 & s2 & s1 & s0; end function;

  function program return imem_t is
    variable m : imem_t := (others => bundle(NOP, NOP, NOP, NOP));
    variable cnt : integer;
  begin
    if PROG /= 3 then
      if PROG = 2 then cnt := 4; else cnt := 8; end if;
      m(0) := bundle(addi(2, 0, 64), addi(7, 0, 3), NOP, NOP);                       -- r2 = &y, r7 = a
      m(1) := bundle(addi(8, 0, cnt), NOP, NOP, NOP);                                -- r8 = iteration count; r1 = &x = 0
    end if;
    if PROG = 0 then                                                                 -- one op per bundle
      m(2)  := bundle(NOP, NOP, ld(3, 1, 0), NOP);
      m(3)  := bundle(NOP, NOP, ld(4, 2, 0), NOP);
      m(4)  := bundle(mul(5, 3, 7), NOP, NOP, NOP);                                  -- r3 landed (load at 2, +2)
      m(5)  := bundle(add(6, 5, 4), NOP, NOP, NOP);
      m(6)  := bundle(NOP, NOP, st(2, 0, 6), NOP);
      m(7)  := bundle(addi(1, 1, 4), NOP, NOP, NOP);
      m(8)  := bundle(addi(2, 2, 4), NOP, NOP, NOP);
      m(9)  := bundle(addi(8, 8, -1), NOP, NOP, NOP);
      m(10) := bundle(NOP, NOP, NOP, bnez(8, 2));
      m(11) := bundle(NOP, NOP, NOP, halt);
    elsif PROG = 1 then                                                              -- packed within an iteration
      m(2)  := bundle(addi(8, 8, -1), NOP, ld(3, 1, 0), NOP);
      m(3)  := bundle(addi(1, 1, 4),  NOP, ld(4, 2, 0), NOP);
      m(4)  := bundle(mul(5, 3, 7), NOP, NOP, NOP);
      m(5)  := bundle(add(6, 5, 4), NOP, NOP, NOP);
      m(6)  := bundle(addi(2, 2, 4), NOP, st(2, 0, 6), bnez(8, 2));                  -- st reads the OLD r2
      m(7)  := bundle(NOP, NOP, NOP, halt);
    elsif PROG = 2 then                                                              -- unrolled x2, software scheduled
      m(2)  := bundle(addi(8, 8, -1), NOP,            ld(3, 1, 0),  NOP);
      m(3)  := bundle(NOP,            NOP,            ld(9, 1, 4),  NOP);
      m(4)  := bundle(mul(5, 3, 7),   addi(1, 1, 8),  ld(4, 2, 0),  NOP);
      m(5)  := bundle(mul(11, 9, 7),  NOP,            ld(10, 2, 4), NOP);
      m(6)  := bundle(add(6, 5, 4),   NOP,            NOP,          NOP);
      m(7)  := bundle(add(12, 11, 10), NOP,           st(2, 0, 6),  NOP);
      m(8)  := bundle(addi(2, 2, 8),  NOP,            st(2, 4, 12), bnez(8, 2));
      m(9)  := bundle(NOP, NOP, NOP, halt);
    else                                                                             -- exposed latency
      m(0) := bundle(addi(3, 0, 77), NOP, NOP, NOP);                                 -- r3 = 77
      m(1) := bundle(NOP, NOP, ld(3, 0, 0), NOP);                                    -- r3 <- mem[0] = 1, lands 2 bundles later
      m(2) := bundle(add(4, 3, 0), NOP, NOP, NOP);                                   -- too early: still reads 77
      m(3) := bundle(add(5, 3, 0), NOP, NOP, NOP);                                   -- load has landed: reads 1
      m(4) := bundle(add(6, 5, 0), add(5, 4, 0), NOP, NOP);                          -- parallel read: r6 = old r5 (1), r5 = old r4 (77)
      m(5) := bundle(NOP, NOP, NOP, halt);
    end if;
    return m;
  end function;
  constant imem : imem_t := program;

  function init_dmem return dmem_t is
    variable d : dmem_t := (others => (others => '0'));
  begin
    for i in 0 to 7 loop
      d(i) := std_logic_vector(to_unsigned(i + 1, 32));
      d(16 + i) := std_logic_vector(to_unsigned(100 * i, 32));
    end loop;
    return d;
  end function;

  signal imem_addr, dmem_addr, dmem_wdata, dmem_rdata, dbg_rdata : word;
  signal imem_rdata : bnd;
  signal dmem_we, halted : std_logic;
  signal dbg_raddr : std_logic_vector(3 downto 0) := (others => '0');
  signal bundles, ops : unsigned(31 downto 0);
  signal dmem : dmem_t := init_dmem;
begin
  dut : entity work.vliw4
    port map (clk, rst_n, imem_addr, imem_rdata, dmem_addr, dmem_wdata, dmem_we, dmem_rdata, dbg_raddr, dbg_rdata, halted, bundles, ops);

  imem_rdata <= imem(to_integer(unsigned(imem_addr(5 downto 0))));
  dmem_rdata <= dmem(to_integer(unsigned(dmem_addr(7 downto 2))));
  process (clk) begin
    if rising_edge(clk) and dmem_we = '1' then dmem(to_integer(unsigned(dmem_addr(7 downto 2)))) <= dmem_wdata; end if;
  end process;

  stim : process
    variable errs : integer := 0;
    variable t : natural := 0;
    procedure check_reg(r : natural; expect_v : integer) is
    begin
      dbg_raddr <= r4(r);  wait for 1 ns;
      if to_integer(unsigned(dbg_rdata)) /= expect_v then
        errs := errs + 1;  report "FAIL [PROG " & integer'image(PROG) & "] r" & integer'image(r) & " = " &
                                  integer'image(to_integer(unsigned(dbg_rdata))) & ", expected " & integer'image(expect_v) severity error;
      end if;
    end procedure;
    procedure check_stat(name : string; got : unsigned; expect_v : natural) is
    begin
      if to_integer(got) /= expect_v then
        errs := errs + 1;  report "FAIL [PROG " & integer'image(PROG) & "] " & name & " = " & integer'image(to_integer(got)) &
                                  ", expected " & integer'image(expect_v) severity error;
      end if;
    end procedure;
  begin
    done <= '0';  errors <= 0;
    wait until rst_n = '1';
    while halted /= '1' and t < 400 loop wait until rising_edge(clk); t := t + 1; end loop;
    if halted /= '1' then errs := errs + 1; report "FAIL: never halted" severity error; end if;
    wait until falling_edge(clk);
    if PROG /= 3 then
      for i in 0 to 7 loop
        if to_integer(unsigned(dmem(16 + i))) /= 103 * i + 3 then
          errs := errs + 1;  report "FAIL [PROG " & integer'image(PROG) & "] y[" & integer'image(i) & "]" severity error;
        end if;
      end loop;
      if PROG = 0 then check_stat("bundles", bundles, 75);
      elsif PROG = 1 then check_stat("bundles", bundles, 43);
      else check_stat("bundles", bundles, 31);
      end if;
      if PROG = 2 then check_stat("ops", ops, 60); else check_stat("ops", ops, 76); end if;
    else
      check_reg(4, 77);  check_reg(5, 77);  check_reg(6, 1);  check_reg(3, 1);
      check_stat("bundles", bundles, 6);  check_stat("ops", ops, 7);
    end if;
    report "PROG " & integer'image(PROG) & ": " & integer'image(to_integer(bundles)) & " bundles, " & integer'image(to_integer(ops)) & " ops";
    errors <= errs;  done <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_vliw4 is end entity;

architecture sim of tb_vliw4 is
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal d : std_logic_vector(3 downto 0);
  type int4 is array (0 to 3) of integer;
  signal er : int4;
begin
  clk <= not clk after 5 ns;
  gen : for p in 0 to 3 generate
    h : entity work.vliw_harness generic map (p) port map (clk, rst_n, d(p), er(p));
  end generate;

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
