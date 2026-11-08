-- Four workloads on an 8-set direct-mapped cache (4-word lines), with and without the stride prefetcher.
--   unit    : pc 1, addresses 0..63 (stride 1 word: 4 accesses per line)
--   stride4 : pc 2, addresses 0,4,8,... (stride = one line: every access touches a new line), 48 accesses
--   random  : pc 3, 120 pseudo-random addresses in 0..255 (no repeating stride)
--   mix     : 40 x { stream pc 2 addr 4i ; hot variable pc 5 addr 12 ; pc 5 addr 13 }  -- the prefetches target sets that the hot line lives in (pollution)
-- Expected (hits, misses, prefetches issued, prefetches useful) from an independent Python functional model.  It is exact in the GAP regime where
-- every prefetch finishes before the next demand access (GAP >= 12 compute cycles between accesses):
--                 prefetch OFF               prefetch ON
--   unit      48 / 16 /  0 /  0       63 /  1 / 16 / 15
--   stride4    0 / 48 /  0 /  0       45 /  3 / 46 / 45
--   random    15 /105 /  0 /  0       15 /105 /  0 /  0     (no stride ever repeats -> nothing is prefetched, nothing is polluted)
--   mix       76 / 44 /  0 /  0      104 / 16 / 37 / 32     (5 of 37 prefetches wasted)
-- Demand-wait cycles in that regime: 1 per hit + (MEM_LAT + 3 = 6) per miss.  With GAP = 0 (back-to-back accesses) the demand stream starves the
-- prefetcher of idle time and a demand access can wait behind a prefetch: only data correctness is checked there; the counters are printed.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pf_harness is
  generic (PREFETCH : boolean := true; GAP : natural := 12);
  port (clk, rst_n : in std_logic; done : out std_logic; errors : out integer);
end entity;

architecture sim of pf_harness is
  constant MEM_LAT : positive := 3;
  constant LINE_WORDS : positive := 4;
  signal local_rst, req_valid, mem_done : std_logic := '0';
  signal dut_rst_n : std_logic;
  signal req_pc : std_logic_vector(7 downto 0) := (others => '0');
  signal req_addr, mem_addr : std_logic_vector(15 downto 0) := (others => '0');
  signal resp_valid, mem_valid : std_logic;
  signal resp_rdata : std_logic_vector(31 downto 0);
  signal mem_rdata : std_logic_vector(LINE_WORDS*32-1 downto 0) := (others => '0');
  signal st_h, st_m, st_i, st_u : unsigned(31 downto 0);

  function word_val(w : natural) return std_logic_vector is
  begin return std_logic_vector(unsigned'(x"FACE0000") + to_unsigned(w, 32)); end function;
begin
  dut_rst_n <= rst_n and not local_rst;
  dut : entity work.stride_prefetcher generic map (SETS => 8, LINE_WORDS => LINE_WORDS, RPT => 4, THRESH => 1, PREFETCH => PREFETCH)
    port map (clk, dut_rst_n, req_valid, req_pc, req_addr, resp_valid, resp_rdata, mem_valid, mem_addr, mem_done, mem_rdata, st_h, st_m, st_i, st_u);

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
    variable wait_cycles : integer := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(2090, 32);

    procedure access_word(pc, addr : natural) is
      variable cyc : natural := 0;
      variable fin : boolean := false;
    begin
      wait until falling_edge(clk);
      req_valid <= '1';  req_pc <= std_logic_vector(to_unsigned(pc, 8));  req_addr <= std_logic_vector(to_unsigned(addr, 16));
      while not fin loop
        wait until rising_edge(clk);
        cyc := cyc + 1;
        if resp_valid = '1' then
          if resp_rdata /= word_val(addr) then errs := errs + 1; report "FAIL wrong data at address " & integer'image(addr) severity error; end if;
          fin := true;
        elsif cyc > 200 then errs := errs + 1; report "FAIL timeout at " & integer'image(addr) severity error; fin := true;
        end if;
      end loop;
      wait_cycles := wait_cycles + cyc;
      wait until falling_edge(clk);
      req_valid <= '0';
      for g in 1 to GAP loop wait until falling_edge(clk); end loop;                -- compute time before the next access
    end procedure;
    procedure fresh is
    begin
      wait until falling_edge(clk);  local_rst <= '1';  wait until falling_edge(clk);  wait until falling_edge(clk);  local_rst <= '0';
      wait_cycles := 0;
    end procedure;
    procedure check(name : string; n, h, m, i, u : natural) is
    begin
      if GAP >= 12 then
        if st_h /= h or st_m /= m or st_i /= i or st_u /= u then
          errs := errs + 1;
          report "FAIL " & name & ": hits=" & integer'image(to_integer(st_h)) & " misses=" & integer'image(to_integer(st_m)) &
                 " issued=" & integer'image(to_integer(st_i)) & " useful=" & integer'image(to_integer(st_u)) severity error;
        end if;
        if wait_cycles /= h + (MEM_LAT + 3) * m then
          errs := errs + 1;  report "FAIL " & name & ": demand-wait cycles " & integer'image(wait_cycles) severity error;
        end if;
      elsif to_integer(st_h) + to_integer(st_m) /= n then
        errs := errs + 1;  report "FAIL " & name & ": hits + misses /= accesses" severity error;
      end if;
      report "GAP=" & integer'image(GAP) & " " & name & ": hits " & integer'image(to_integer(st_h)) & " misses " & integer'image(to_integer(st_m)) &
             " prefetches " & integer'image(to_integer(st_i)) & " (useful " & integer'image(to_integer(st_u)) & ") demand-wait " & integer'image(wait_cycles);
    end procedure;
  begin
    done <= '0';  errors <= 0;
    wait until rst_n = '1';

    fresh;  for a in 0 to 63 loop access_word(1, a); end loop;
    if PREFETCH then check("unit", 64, 63, 1, 16, 15); else check("unit", 64, 48, 16, 0, 0); end if;
    fresh;  for i in 0 to 47 loop access_word(2, 4 * i); end loop;
    if PREFETCH then check("stride4", 48, 45, 3, 46, 45); else check("stride4", 48, 0, 48, 0, 0); end if;
    fresh;
    for i in 0 to 119 loop
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
      access_word(3, to_integer(seed(31 downto 16)) mod 256);
    end loop;
    check("random", 120, 15, 105, 0, 0);
    fresh;  for i in 0 to 39 loop access_word(2, 4 * i); access_word(5, 12); access_word(5, 13); end loop;
    if PREFETCH then check("mix", 120, 104, 16, 37, 32); else check("mix", 120, 76, 44, 0, 0); end if;
    errors <= errs;  done <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_stride_prefetcher is end entity;

architecture sim of tb_stride_prefetcher is
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal d : std_logic_vector(3 downto 0);
  type int4 is array (0 to 3) of integer;
  signal er : int4;
begin
  clk <= not clk after 5 ns;
  off12 : entity work.pf_harness generic map (false, 12) port map (clk, rst_n, d(0), er(0));
  on12  : entity work.pf_harness generic map (true, 12)  port map (clk, rst_n, d(1), er(1));
  off0  : entity work.pf_harness generic map (false, 0)  port map (clk, rst_n, d(2), er(2));
  on0   : entity work.pf_harness generic map (true, 0)   port map (clk, rst_n, d(3), er(3));

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
