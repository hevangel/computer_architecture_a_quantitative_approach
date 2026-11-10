-- Exhaustive litmus tests.  For every program the testbench enumerates ALL schedules (depth-first over the enabled actions, re-running the machine from reset for each schedule) and
-- collects the set of final outcomes (under SC the number of schedules is the multinomial coefficient of the program lengths: SB 4!/(2!2!) = 6, SB+fences 6!/(3!3!) = 20, MP 6, MP+fence 5!/(3!2!) = 10, LB 6, IRIW 6!/(1!1!2!2!) = 180, SBF 20, WRC 5!/(1!2!2!) = 30); it must equal the set derived by hand for the model -- no forbidden outcome may ever appear, every allowed outcome must appear.
-- x = address 0, y = address 1, all initially 0, every store writes 1.   Outcome = the observed registers, written as a tuple.
--   SB   P0: x=1; r0=y    P1: y=1; r0=x       (P0.r0, P1.r0)    SC {01,10,11} (not 00: some store comes first);  TSO, PSO {00,01,10,11}: each store may still sit in its buffer while the other core loads
--   SB+F same with a FENCE between the store and the load in both cores: {01,10,11} in all three models
--   MP   P0: x=1; y=1     P1: r0=y; r1=x      (P1.r0, P1.r1)    SC, TSO {00,01,11} (not 10: stores drain in order, loads execute in order);  PSO all four (y may drain before x)
--   MP+F a FENCE between P0's two stores: {00,01,11} in all three models
--   LB   P0: r0=x; y=1    P1: r0=y; x=1       (P0.r0, P1.r0)    {00,01,10} in all three (loads execute in order before the later store: 11 needs load reordering, allowed on ARM/POWER)
--   IRIW P0: x=1  P1: y=1  P2: r0=x; r1=y  P3: r0=y; r1=x   (P2.r0,P2.r1,P3.r0,P3.r1)    every outcome except 1010 in all three models (two readers never disagree on the order of two independent
--        writes: memory is multi-copy atomic here)
--   SBF  P0: x=1; r0=x; r1=y   P1: y=1; r0=y; r1=x    (P0.r0,P0.r1,P1.r0,P1.r1)    SC {1011,1110,1111};  TSO, PSO add 1010: each core reads its own store FROM ITS BUFFER (r0 = 1) before it is visible to the other
--   WRC  P0: x=1   P1: r0=x; y=1   P2: r0=y; r1=x    (P1.r0, P2.r0, P2.r1)    every outcome except 110 in all three models (causality: if P1 saw x=1 before writing y, P2 seeing y=1 must see x=1)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package lit_pkg is
  type nat8_t is array (0 to 7) of natural;
end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.lit_pkg.all;

entity lit_harness is
  generic (MODEL : natural := 0);
  port (done : out std_logic; errors : out natural; runs_total : out natural; runs_t, nout_t : out nat8_t);
end entity;

architecture sim of lit_harness is
  constant P : natural := 4;  constant L : natural := 3;  constant NT : natural := 8;
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal local_rst : std_logic := '0';
  signal dut_rst_n : std_logic;
  signal prog : std_logic_vector(P*L*8-1 downto 0) := (others => '0');
  signal act_valid : std_logic := '0';
  signal act : natural range 0 to 255 := 0;
  signal enabled : std_logic_vector(P+P*3-1 downto 0);
  signal regs : std_logic_vector(P*2*4-1 downto 0);
  signal memv : std_logic_vector(15 downto 0);
begin
  clk <= not clk after 5 ns;
  dut_rst_n <= rst_n and not local_rst;
  dut : entity work.consistency_model
    generic map (MODEL => MODEL, P => P, L => L, SBD => 3)
    port map (clk => clk, rst_n => dut_rst_n, prog => prog, act_valid => act_valid, act => act, enabled => enabled, regs => regs, memv => memv);

  main : process
    type pg_t is array (0 to NT-1, 0 to P-1, 0 to L-1) of std_logic_vector(7 downto 0);
    type int_arr is array (natural range <>) of integer;
    type mask_arr is array (0 to NT-1) of std_logic_vector(15 downto 0);
    variable pg : pg_t := (others => (others => (others => (others => '0'))));
    variable nobs : int_arr(0 to NT-1) := (others => 0);
    type obs_t is array (0 to NT-1, 0 to 3) of integer;
    variable obs_c, obs_r : obs_t := (others => (others => 0));
    variable exp_sc, exp_tso, exp_pso : mask_arr := (others => (others => '0'));
    variable runs, nout : nat8_t := (others => 0);
    variable path, nch : int_arr(0 to 63) := (others => 0);
    variable depth, nerr, runs_all : integer := 0;
    variable seen, want_mask : std_logic_vector(15 downto 0);
    variable more : boolean;

    function ins(op, ad, arg : integer) return std_logic_vector is
    begin
      return std_logic_vector(to_unsigned(op, 2)) & std_logic_vector(to_unsigned(ad, 2)) & std_logic_vector(to_unsigned(arg, 4));
    end function;
    -- one outcome tuple -> its bit in the set
    function mask(n, a, b, c, d : integer) return std_logic_vector is
      variable code : integer;
      variable r : std_logic_vector(15 downto 0) := (others => '0');
    begin
      if n = 2 then code := a*2 + b; elsif n = 3 then code := a*4 + b*2 + c; else code := a*8 + b*4 + c*2 + d; end if;
      r(code) := '1';
      return r;
    end function;
    constant OPST : integer := 1;  constant OPLD : integer := 2;  constant OPFN : integer := 3;

    procedure define_tests is
    begin
      -- 0 SB
      pg(0,0,0) := ins(OPST,0,1);  pg(0,0,1) := ins(OPLD,1,0);   pg(0,1,0) := ins(OPST,1,1);  pg(0,1,1) := ins(OPLD,0,0);
      nobs(0) := 2;  obs_c(0,0) := 0; obs_r(0,0) := 0;  obs_c(0,1) := 1; obs_r(0,1) := 0;
      exp_sc(0) := mask(2,0,1,0,0) or mask(2,1,0,0,0) or mask(2,1,1,0,0);   exp_tso(0) := exp_sc(0) or mask(2,0,0,0,0);   exp_pso(0) := exp_tso(0);
      -- 1 SB + fences
      pg(1,0,0) := ins(OPST,0,1);  pg(1,0,1) := ins(OPFN,0,0);  pg(1,0,2) := ins(OPLD,1,0);   pg(1,1,0) := ins(OPST,1,1);  pg(1,1,1) := ins(OPFN,0,0);  pg(1,1,2) := ins(OPLD,0,0);
      nobs(1) := 2;  obs_c(1,0) := 0; obs_r(1,0) := 0;  obs_c(1,1) := 1; obs_r(1,1) := 0;
      exp_sc(1) := exp_sc(0);  exp_tso(1) := exp_sc(0);  exp_pso(1) := exp_sc(0);
      -- 2 MP
      pg(2,0,0) := ins(OPST,0,1);  pg(2,0,1) := ins(OPST,1,1);   pg(2,1,0) := ins(OPLD,1,0);  pg(2,1,1) := ins(OPLD,0,1);
      nobs(2) := 2;  obs_c(2,0) := 1; obs_r(2,0) := 0;  obs_c(2,1) := 1; obs_r(2,1) := 1;
      exp_sc(2) := mask(2,0,0,0,0) or mask(2,0,1,0,0) or mask(2,1,1,0,0);   exp_tso(2) := exp_sc(2);   exp_pso(2) := exp_sc(2) or mask(2,1,0,0,0);
      -- 3 MP + fence between the stores
      pg(3,0,0) := ins(OPST,0,1);  pg(3,0,1) := ins(OPFN,0,0);  pg(3,0,2) := ins(OPST,1,1);   pg(3,1,0) := ins(OPLD,1,0);  pg(3,1,1) := ins(OPLD,0,1);
      nobs(3) := 2;  obs_c(3,0) := 1; obs_r(3,0) := 0;  obs_c(3,1) := 1; obs_r(3,1) := 1;
      exp_sc(3) := exp_sc(2);  exp_tso(3) := exp_sc(2);  exp_pso(3) := exp_sc(2);
      -- 4 LB
      pg(4,0,0) := ins(OPLD,0,0);  pg(4,0,1) := ins(OPST,1,1);   pg(4,1,0) := ins(OPLD,1,0);  pg(4,1,1) := ins(OPST,0,1);
      nobs(4) := 2;  obs_c(4,0) := 0; obs_r(4,0) := 0;  obs_c(4,1) := 1; obs_r(4,1) := 0;
      exp_sc(4) := mask(2,0,0,0,0) or mask(2,0,1,0,0) or mask(2,1,0,0,0);   exp_tso(4) := exp_sc(4);   exp_pso(4) := exp_sc(4);
      -- 5 IRIW
      pg(5,0,0) := ins(OPST,0,1);  pg(5,1,0) := ins(OPST,1,1);
      pg(5,2,0) := ins(OPLD,0,0);  pg(5,2,1) := ins(OPLD,1,1);   pg(5,3,0) := ins(OPLD,1,0);  pg(5,3,1) := ins(OPLD,0,1);
      nobs(5) := 4;  obs_c(5,0) := 2; obs_r(5,0) := 0;  obs_c(5,1) := 2; obs_r(5,1) := 1;  obs_c(5,2) := 3; obs_r(5,2) := 0;  obs_c(5,3) := 3; obs_r(5,3) := 1;
      exp_sc(5) := x"FFFF" and not mask(4,1,0,1,0);   exp_tso(5) := exp_sc(5);   exp_pso(5) := exp_sc(5);
      -- 6 SB with forwarding
      pg(6,0,0) := ins(OPST,0,1);  pg(6,0,1) := ins(OPLD,0,0);  pg(6,0,2) := ins(OPLD,1,1);   pg(6,1,0) := ins(OPST,1,1);  pg(6,1,1) := ins(OPLD,1,0);  pg(6,1,2) := ins(OPLD,0,1);
      nobs(6) := 4;  obs_c(6,0) := 0; obs_r(6,0) := 0;  obs_c(6,1) := 0; obs_r(6,1) := 1;  obs_c(6,2) := 1; obs_r(6,2) := 0;  obs_c(6,3) := 1; obs_r(6,3) := 1;
      exp_sc(6) := mask(4,1,0,1,1) or mask(4,1,1,1,0) or mask(4,1,1,1,1);   exp_tso(6) := exp_sc(6) or mask(4,1,0,1,0);   exp_pso(6) := exp_tso(6);
      -- 7 WRC
      pg(7,0,0) := ins(OPST,0,1);   pg(7,1,0) := ins(OPLD,0,0);  pg(7,1,1) := ins(OPST,1,1);   pg(7,2,0) := ins(OPLD,1,0);  pg(7,2,1) := ins(OPLD,0,1);
      nobs(7) := 3;  obs_c(7,0) := 1; obs_r(7,0) := 0;  obs_c(7,1) := 2; obs_r(7,1) := 0;  obs_c(7,2) := 2; obs_r(7,2) := 1;
      exp_sc(7) := x"00FF" and not mask(3,1,1,0,0);   exp_tso(7) := exp_sc(7);   exp_pso(7) := exp_sc(7);
    end procedure;

    -- run the machine once, following `path`; record the number of choices at each step and the final outcome
    procedure one_run(t : integer) is
      variable d, cnt, want, pick, code, val : integer;
      variable fin : boolean;
    begin
      wait until falling_edge(clk);  local_rst <= '1';  act_valid <= '0';  wait until falling_edge(clk);  wait until falling_edge(clk);  local_rst <= '0';
      for c in 0 to P-1 loop for k in 0 to L-1 loop prog((c*L + k)*8 + 7 downto (c*L + k)*8) <= pg(t, c, k); end loop; end loop;
      d := 0;  fin := false;
      while not fin loop
        wait until falling_edge(clk);  act_valid <= '0';  wait for 1 ns;
        cnt := 0;  for a in 0 to P + P*3 - 1 loop if enabled(a) = '1' then cnt := cnt + 1; end if; end loop;
        if cnt = 0 then fin := true;
        else
          nch(d) := cnt;
          want := path(d);  pick := -1;  cnt := 0;
          for a in 0 to P + P*3 - 1 loop
            if enabled(a) = '1' then
              if cnt = want then pick := a; end if;
              cnt := cnt + 1;
            end if;
          end loop;
          act_valid <= '1';  act <= pick;
          d := d + 1;
        end if;
      end loop;
      depth := d;
      code := 0;
      for i in 0 to nobs(t) - 1 loop
        val := to_integer(unsigned(regs((obs_c(t,i)*2 + obs_r(t,i))*4 + 3 downto (obs_c(t,i)*2 + obs_r(t,i))*4)));
        if val > 1 then nerr := nerr + 1; report "FAIL [model " & integer'image(MODEL) & " test " & integer'image(t) & "] register value " & integer'image(val) severity note; end if;
        code := code * 2 + (val mod 2);
      end loop;
      seen(code) := '1';
    end procedure;
    type sc_t is array (0 to NT-1) of integer;
    constant sc_runs : sc_t := (6, 20, 6, 10, 6, 180, 20, 30);
  begin
    done <= '0';  errors <= 0;  runs_total <= 0;  runs_t <= (others => 0);  nout_t <= (others => 0);
    define_tests;
    wait until falling_edge(clk);  wait until falling_edge(clk);  wait until falling_edge(clk);  rst_n <= '1';
    wait until falling_edge(clk);  wait until falling_edge(clk);
    for t in 0 to NT-1 loop
      path := (others => 0);  nch := (others => 0);
      seen := (others => '0');  runs(t) := 0;  more := true;
      while more loop
        one_run(t);
        runs(t) := runs(t) + 1;
        -- next schedule: odometer over the choices (deepest position that still has an unused alternative)
        more := false;
        for k in 63 downto 0 loop
          if k < depth and not more then
            if path(k) + 1 < nch(k) then
              path(k) := path(k) + 1;  more := true;
              for j in 0 to 63 loop if j > k then path(j) := 0; end if; end loop;
            end if;
          end if;
        end loop;
      end loop;
      if MODEL = 0 then want_mask := exp_sc(t); elsif MODEL = 1 then want_mask := exp_tso(t); else want_mask := exp_pso(t); end if;
      nout(t) := 0;  for i in 0 to 15 loop if seen(i) = '1' then nout(t) := nout(t) + 1; end if; end loop;
      if seen /= want_mask then
        nerr := nerr + 1;  report "FAIL [model " & integer'image(MODEL) & " test " & integer'image(t) & "] outcomes seen differ from the hand-derived set (after " & integer'image(runs(t)) & " schedules)" severity note;
      end if;
      if MODEL = 0 and runs(t) /= sc_runs(t) then
        nerr := nerr + 1;  report "FAIL [SC test " & integer'image(t) & "] " & integer'image(runs(t)) & " schedules, expected " & integer'image(sc_runs(t)) & " (a multinomial coefficient)" severity note;
      end if;
      runs_all := runs_all + runs(t);
    end loop;
    runs_total <= runs_all;  runs_t <= runs;  nout_t <= nout;
    errors <= nerr;  done <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
use work.lit_pkg.all;

entity tb_memory_consistency is end entity;

architecture sim of tb_memory_consistency is
  signal d0, d1, d2 : std_logic;
  signal e0, e1, e2, n0, n1, n2 : natural;
  signal r0, r1, r2, o0, o1, o2 : nat8_t;
begin
  sc  : entity work.lit_harness generic map (0) port map (d0, e0, n0, r0, o0);
  tso : entity work.lit_harness generic map (1) port map (d1, e1, n1, r1, o1);
  pso : entity work.lit_harness generic map (2) port map (d2, e2, n2, r2, o2);

  process
    type names_t is array (0 to 7) of string(1 to 14);
    constant names : names_t := ("SB            ", "SB+fences     ", "MP            ", "MP+fence      ", "LB            ", "IRIW          ", "SB+forwarding ", "WRC           ");
    variable errors : integer;
  begin
    wait until d0 = '1' and d1 = '1' and d2 = '1';
    errors := e0 + e1 + e2;
    report "schedules explored: SC " & integer'image(n0) & ", TSO " & integer'image(n1) & ", PSO " & integer'image(n2) severity note;
    for t in 0 to 7 loop
      report names(t) & " schedules (SC/TSO/PSO) " & integer'image(r0(t)) & " / " & integer'image(r1(t)) & " / " & integer'image(r2(t)) &
             "   distinct outcomes (SC/TSO/PSO) " & integer'image(o0(t)) & " / " & integer'image(o1(t)) & " / " & integer'image(o2(t)) severity note;
    end loop;
    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED: " & integer'image(errors) & " errors" severity error; end if;
    finish;
  end process;
end architecture;
