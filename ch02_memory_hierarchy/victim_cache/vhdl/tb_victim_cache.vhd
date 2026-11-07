-- Three traces on a 4-set direct-mapped cache with 0 / 1 / 2 / 4 victim entries.  Lines 0, 4, 8 all map to set 0.
--   alt    : 0 4 0 4 ... (12 accesses)       two lines fight for one set
--   three  : 0 4 8 0 4 8 ... (12 accesses)   three lines fight for one set
--   random : 400 accesses over lines 0..11   (LCG)
-- Expected (l1 hits, victim hits, misses) come from an independent Python model of LRU victim replacement:
--              V=0            V=1            V=2            V=4
--   alt      0/  0/ 12      0/ 10/  2      0/ 10/  2      0/ 10/  2
--   three    0/  0/ 12      0/  0/ 12      0/  9/  3      0/  9/  3
--   random 134/  0/266    134/ 32/234    134/ 75/191    134/141/125
-- Cycle cost per access: L1 hit 1, victim hit 2, miss MEM_LAT + 3 (= 6 here) -> total cycles are checked against that formula.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vc_harness is
  generic (VICT : natural := 2);
  port (clk, rst_n : in std_logic; done : out std_logic; errors : out integer);
end entity;

architecture sim of vc_harness is
  constant MEM_LAT : positive := 3;
  constant LINE_WORDS : positive := 4;
  signal local_rst, req_valid, mem_done : std_logic := '0';
  signal dut_rst_n : std_logic;
  signal req_addr, mem_addr : std_logic_vector(15 downto 0) := (others => '0');
  signal resp_valid, mem_valid : std_logic;
  signal resp_rdata : std_logic_vector(31 downto 0);
  signal mem_rdata : std_logic_vector(LINE_WORDS*32-1 downto 0) := (others => '0');
  signal st_l1, st_vic, st_miss : unsigned(31 downto 0);

  function word_val(w : natural) return std_logic_vector is
  begin return std_logic_vector(unsigned'(x"C0DE0000") + to_unsigned(w, 32)); end function;
begin
  dut_rst_n <= rst_n and not local_rst;
  dut : entity work.victim_cache generic map (SETS => 4, LINE_WORDS => LINE_WORDS, VICT => VICT)
    port map (clk, dut_rst_n, req_valid, req_addr, resp_valid, resp_rdata, mem_valid, mem_addr, mem_done, mem_rdata, st_l1, st_vic, st_miss);

  memory : process (clk)
    variable cnt : natural := 0;
  begin
    if rising_edge(clk) then
      mem_done <= '0';
      if mem_valid = '1' and mem_done = '0' then
        if cnt = MEM_LAT - 1 then
          cnt := 0;  mem_done <= '1';
          for k in 0 to LINE_WORDS-1 loop
            mem_rdata((k+1)*32-1 downto k*32) <= word_val(to_integer(unsigned(mem_addr)) * LINE_WORDS + k);
          end loop;
        else cnt := cnt + 1;
        end if;
      else cnt := 0;
      end if;
    end if;
  end process;

  stim : process
    variable errs : integer := 0;
    variable total_cycles : integer := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(2088, 32);

    procedure access_line(ln, off : natural) is
      variable cyc : natural := 0;
      variable fin : boolean := false;
    begin
      wait until falling_edge(clk);
      req_valid <= '1';  req_addr <= std_logic_vector(to_unsigned(ln * LINE_WORDS + off, 16));
      while not fin loop
        wait until rising_edge(clk);
        cyc := cyc + 1;
        if resp_valid = '1' then
          if resp_rdata /= word_val(ln * LINE_WORDS + off) then errs := errs + 1; report "FAIL [V=" & integer'image(VICT) & "] wrong data" severity error; end if;
          fin := true;
        elsif cyc > 100 then errs := errs + 1; report "FAIL timeout" severity error; fin := true;
        end if;
      end loop;
      total_cycles := total_cycles + cyc;
      wait until falling_edge(clk);
      req_valid <= '0';
    end procedure;
    procedure fresh is
    begin
      wait until falling_edge(clk);  local_rst <= '1';  wait until falling_edge(clk);  wait until falling_edge(clk);  local_rst <= '0';
      total_cycles := 0;
    end procedure;
    procedure check(name : string; h, vh, m : natural) is
    begin
      if st_l1 /= h or st_vic /= vh or st_miss /= m then
        errs := errs + 1;
        report "FAIL [V=" & integer'image(VICT) & "] " & name & ": l1=" & integer'image(to_integer(st_l1)) & " victim=" &
               integer'image(to_integer(st_vic)) & " miss=" & integer'image(to_integer(st_miss)) severity error;
      end if;
      if total_cycles /= h + 2*vh + (MEM_LAT + 3)*m then
        errs := errs + 1;
        report "FAIL [V=" & integer'image(VICT) & "] " & name & ": " & integer'image(total_cycles) & " cycles, expected " &
               integer'image(h + 2*vh + (MEM_LAT + 3)*m) severity error;
      end if;
    end procedure;
  begin
    done <= '0';  errors <= 0;
    wait until rst_n = '1';

    fresh;  for i in 0 to 11 loop access_line((i mod 2) * 4, 0); end loop;
    if VICT = 0 then check("alt", 0, 0, 12); else check("alt", 0, 10, 2); end if;

    fresh;  for i in 0 to 11 loop access_line((i mod 3) * 4, 0); end loop;
    if VICT <= 1 then check("three", 0, 0, 12); else check("three", 0, 9, 3); end if;

    fresh;
    for i in 0 to 399 loop
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
      access_line(to_integer(seed(31 downto 16)) mod 12, to_integer(seed(9 downto 8)));
    end loop;
    if VICT = 0 then check("random", 134, 0, 266);
    elsif VICT = 1 then check("random", 134, 32, 234);
    elsif VICT = 2 then check("random", 134, 75, 191);
    else check("random", 134, 141, 125);
    end if;
    report "V=" & integer'image(VICT) & ": random trace " & integer'image(to_integer(st_miss)) & " memory fetches, " & integer'image(total_cycles) & " cycles";
    errors <= errs;  done <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_victim_cache is end entity;

architecture sim of tb_victim_cache is
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal d : std_logic_vector(3 downto 0);
  type int4 is array (0 to 3) of integer;
  signal er : int4;
begin
  clk <= not clk after 5 ns;
  v0 : entity work.vc_harness generic map (0) port map (clk, rst_n, d(0), er(0));
  v1 : entity work.vc_harness generic map (1) port map (clk, rst_n, d(1), er(1));
  v2 : entity work.vc_harness generic map (2) port map (clk, rst_n, d(2), er(2));
  v4 : entity work.vc_harness generic map (4) port map (clk, rst_n, d(3), er(3));

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
