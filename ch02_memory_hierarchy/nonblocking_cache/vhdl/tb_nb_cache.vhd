-- Memory: MEM_LAT 10, a write occupies the memory port for 4 cycles (WR_OCC), a read for 1.  Cycle numbers are relative to the first accepted request (cycle 0).
-- Hand-derived expectations ("acc" = cycle a request is accepted, "resp" = cycle its answer appears on the hit or fill port):
--   read hit : resp = acc + 1.        read miss on an idle cache: request to memory at acc+1, line back at acc+11, answered at acc+12.
--   hit under miss    : R0 miss @0, R1 hit @1      -> non-blocking: acc 1, resp 2;  blocking: R1 waits for the miss, acc 13, resp 14
--   miss under miss   : R0 miss @0, R1 miss @1     -> NM >= 2: resp 12, 13;  one MSHR (or blocking): R1 acc 13, resp 25
--   secondary misses  : words 0..3 of ONE line @0,1,2,3 -> one fetch, answers at 12,13,14,15 (blocking: later words hit: acc 13,14,15 resp 14,15,16);
--                       a fifth read of the line @4 hits as soon as the line is installed: acc 12, resp 13 (blocking: acc 16, resp 17)
--   write buffer vs read: W(A) @0, W(L) @1, R(L) @2 (same line L as the second write): the first write holds the memory port c1..c4, the second drains at c5..c8,
--                       so the line fetch may leave only at c9: resp 9 + 10 + 1 = 20, and the read returns the BUFFERED value
--   write to a line with a miss outstanding: R miss @0, W same line @1 -> W acc 13 (after the 12-cycle miss), a later read of it hits with the new value
--   eight writes to distinct words, presented every cycle, accepted at cycle:
--        WBD 0: 0 4 8 12 16 20 24 28     WBD 1: 0 2 6 10 14 18 22 26     WBD 2: 0 1 2 6 10 14 18 22     WBD 4: 0 1 2 3 4 6 10 14
--        (one memory write per 4 cycles in steady state; the buffer only absorbs the burst)
-- Then three random request streams (hot region / wide / write heavy): every read must return the program-order value, and after the machine drains main
-- memory must equal the shadow memory.

-- One harness entity per configuration (one process owns all state); the top compares the cycle counts the harnesses report.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nbc_harness is
  generic (NM : positive := 4; HUM : boolean := true; WBD : natural := 4);
  port (fin : out std_logic; errs : out natural; tot_a, tot_b, tot_c : out natural);
end entity;

architecture sim of nbc_harness is
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal req_valid, req_write : std_logic := '0';
  signal req_addr : natural range 0 to 255 := 0;
  signal req_wdata : std_logic_vector(31 downto 0) := (others => '0');
  signal req_id : natural range 0 to 63 := 0;
  signal req_ready, hit_valid, fill_valid, mem_valid, mem_write, mem_ready, mem_rvalid, violation : std_logic;
  signal hit_id, fill_id : natural range 0 to 63;
  signal hit_data, fill_data, mem_wdata, dbg_data : std_logic_vector(31 downto 0);
  signal mem_addr : natural range 0 to 255;
  signal mem_tag, mem_rtag : natural range 0 to 3;
  signal mem_rline : std_logic_vector(127 downto 0);
  signal st_hit, st_pri, st_sec : natural;
  signal dbg_addr : natural range 0 to 255 := 0;
begin
  clk <= not clk after 5 ns;

  dut : entity work.nb_cache
    generic map (NM => NM, HUM => HUM, WBD => WBD)
    port map (clk => clk, rst_n => rst_n, req_valid => req_valid, req_write => req_write, req_addr => req_addr, req_wdata => req_wdata, req_id => req_id,
              req_ready => req_ready, hit_valid => hit_valid, hit_id => hit_id, hit_data => hit_data, fill_valid => fill_valid, fill_id => fill_id,
              fill_data => fill_data, mem_valid => mem_valid, mem_write => mem_write, mem_addr => mem_addr, mem_wdata => mem_wdata, mem_tag => mem_tag,
              mem_ready => mem_ready, mem_rvalid => mem_rvalid, mem_rtag => mem_rtag, mem_rline => mem_rline,
              stat_hit => st_hit, stat_pri => st_pri, stat_sec => st_sec);
  mem : entity work.nb_mem
    port map (clk => clk, rst_n => rst_n, mem_valid => mem_valid, mem_write => mem_write, mem_addr => mem_addr, mem_wdata => mem_wdata, mem_tag => mem_tag,
              mem_ready => mem_ready, mem_rvalid => mem_rvalid, mem_rtag => mem_rtag, mem_rline => mem_rline, dbg_addr => dbg_addr, dbg_data => dbg_data,
              violation => violation);

  main : process
    constant MAXR : natural := 512;
    type int_arr  is array (natural range <>) of integer;
    type word_arr is array (natural range <>) of unsigned(31 downto 0);
    type bool_arr is array (natural range <>) of boolean;
    variable r_write : bool_arr(0 to MAXR-1);
    variable r_addr, r_time, acc_c, resp_c : int_arr(0 to MAXR-1) := (others => 0);
    variable id_req : int_arr(0 to 63) := (others => 0);
    variable r_wdata, r_exp : word_arr(0 to MAXR-1);
    variable shadow : word_arr(0 to 255);
    variable n_req, ptr, completed, cyc, nerr : integer := 0;
    variable wseed : unsigned(31 downto 0) := to_unsigned(77, 32);
    variable seed  : unsigned(31 downto 0) := to_unsigned(2013, 32);
    variable p0, s0, h0 : integer;
    variable nb, multi : boolean;
    variable tab : int_arr(0 to 7);
    variable t_a, t_b, t_c : integer := 0;

    impure function rnd(n : positive) return integer is
    begin
      seed := resize(seed * to_unsigned(1664525, 32), 32) + to_unsigned(1013904223, 32);
      return to_integer(seed(30 downto 16)) mod n;
    end function;

    -- one clock cycle: observe the rising edge (responses), then drive the next due request at the falling edge
    procedure neg is
      variable k : integer;
    begin
      wait until rising_edge(clk);
      if rst_n = '1' then
        if hit_valid = '1' then
          k := id_req(hit_id);  resp_c(k) := cyc;  completed := completed + 1;
          if unsigned(hit_data) /= r_exp(k) then nerr := nerr + 1; report "FAIL read " & integer'image(k) & " (addr " & integer'image(r_addr(k)) & ") hit data " & to_hstring(hit_data) & " expected " & to_hstring(r_exp(k)) severity note; end if;
        end if;
        if fill_valid = '1' then
          k := id_req(fill_id);  resp_c(k) := cyc;  completed := completed + 1;
          if unsigned(fill_data) /= r_exp(k) then nerr := nerr + 1; report "FAIL read " & integer'image(k) & " (addr " & integer'image(r_addr(k)) & ") fill data " & to_hstring(fill_data) & " expected " & to_hstring(r_exp(k)) severity note; end if;
        end if;
        if violation = '1' and nerr = 0 then nerr := nerr + 1; report "FAIL: cache presented a request to a busy memory" severity note; end if;
      end if;
      cyc := cyc + 1;
      wait until falling_edge(clk);
      if rst_n = '1' then
        req_valid <= '0';
        if ptr < n_req and cyc >= r_time(ptr) then
          req_valid <= '1';
          if r_write(ptr) then req_write <= '1'; else req_write <= '0'; end if;
          req_addr <= r_addr(ptr);  req_wdata <= std_logic_vector(r_wdata(ptr));  req_id <= ptr mod 64;
          wait for 1 ns;
          if req_ready = '1' then
            id_req(ptr mod 64) := ptr;  acc_c(ptr) := cyc;
            if r_write(ptr) then completed := completed + 1; end if;
            ptr := ptr + 1;
          end if;
        end if;
      end if;
    end procedure;

    procedure clear is begin n_req := 0; ptr := 0; completed := 0; end procedure;
    procedure submit(wr : boolean; addr : integer; t : integer) is
    begin
      wseed := resize(wseed * to_unsigned(1664525, 32), 32) + to_unsigned(1013904223, 32);
      r_write(n_req) := wr;  r_addr(n_req) := addr;  r_time(n_req) := cyc + 3 + t;  r_wdata(n_req) := wseed;  r_exp(n_req) := shadow(addr);
      resp_c(n_req) := -1;  acc_c(n_req) := -1;
      if wr then shadow(addr) := wseed; end if;
      n_req := n_req + 1;
    end procedure;
    procedure idle(n : integer) is begin for i in 1 to n loop neg; end loop; end procedure;
    procedure run(timeout : integer; what : string) is
      variable t : integer := 0;
    begin
      while completed < n_req and t < timeout loop neg; t := t + 1; end loop;
      if completed < n_req then
        nerr := nerr + 1;
        report "FAIL [" & what & "] " & integer'image(completed) & " of " & integer'image(n_req) & " requests completed in " & integer'image(timeout) & " cycles" severity note;
      end if;
      idle(40);
    end procedure;
    procedure expect_i(what : string; got, exp_v : integer) is
    begin
      if got /= exp_v then nerr := nerr + 1; report "FAIL " & what & ": got " & integer'image(got) & " expected " & integer'image(exp_v) severity note; end if;
    end procedure;
    impure function rel_acc(i : integer) return integer is begin return acc_c(i) - acc_c(0); end function;
    impure function rel_resp(i : integer) return integer is begin return resp_c(i) - acc_c(0); end function;

    procedure stream(wr_pct, hot_pct, n : integer; total : out integer) is
      variable rw, rh, a64, a256, gap, tc, last, ad : integer;
    begin
      clear;  tc := 0;
      for i in 0 to n - 1 loop
        rw := rnd(100);  rh := rnd(100);  a64 := rnd(64);  a256 := rnd(256);  gap := rnd(3);
        tc := tc + gap;
        if rh < hot_pct then ad := a64; else ad := a256; end if;
        submit(rw < wr_pct, ad, tc);
      end loop;
      run(20000, "stream");
      last := 0;
      for i in 0 to n - 1 loop
        if acc_c(i) > last then last := acc_c(i); end if;
        if resp_c(i) > last then last := resp_c(i); end if;
      end loop;
      total := last - acc_c(0);
      idle(100);
      for a in 0 to 255 loop
        dbg_addr <= a;  wait for 1 ns;
        if unsigned(dbg_data) /= shadow(a) then
          nerr := nerr + 1;  if nerr < 5 then report "FAIL main memory word " & integer'image(a) & " wrong" severity note; end if;
        end if;
      end loop;
    end procedure;
  begin
    fin <= '0';  errs <= 0;  tot_a <= 0;  tot_b <= 0;  tot_c <= 0;
    for a in 0 to 255 loop shadow(a) := x"5A000000" + to_unsigned(a * 17, 32); end loop;
    nb := HUM;  multi := HUM and NM >= 2;
    for i in 1 to 3 loop neg; end loop;
    rst_n <= '1';
    for i in 1 to 8 loop neg; end loop;

    -- ---- T1: hit and miss latencies, conflict miss ----
    clear;  submit(false, 36, 0);   run(100, "miss");     expect_i("read miss latency", rel_resp(0), 12);
    clear;  submit(false, 37, 0);   run(100, "hit");      expect_i("read hit latency", rel_resp(0), 1);
    clear;  submit(false, 100, 0);  run(100, "conflict"); expect_i("conflict miss latency", rel_resp(0), 12);
    clear;  submit(false, 36, 0);   run(100, "evicted");  expect_i("evicted line misses again", rel_resp(0), 12);

    -- ---- T2: hit under miss ----
    clear;  submit(false, 8, 0);  run(100, "preload");
    clear;  submit(false, 68, 0);  submit(false, 9, 1);  run(200, "hit under miss");
    expect_i("T2 miss resp", rel_resp(0), 12);
    if nb then expect_i("T2 hit acc", rel_acc(1), 1);  expect_i("T2 hit resp", rel_resp(1), 2);
    else       expect_i("T2 hit acc", rel_acc(1), 13); expect_i("T2 hit resp", rel_resp(1), 14); end if;

    -- ---- T3: miss under miss ----
    clear;  submit(false, 160, 0);  submit(false, 172, 1);  run(200, "miss under miss");
    expect_i("T3 first resp", rel_resp(0), 12);
    if multi then expect_i("T3 second acc", rel_acc(1), 1);  expect_i("T3 second resp", rel_resp(1), 13);
    else          expect_i("T3 second acc", rel_acc(1), 13); expect_i("T3 second resp", rel_resp(1), 25); end if;

    -- ---- T4: secondary misses ----
    p0 := st_pri;  s0 := st_sec;  h0 := st_hit;
    clear;  submit(false, 192, 0);  submit(false, 193, 1);  submit(false, 194, 2);  submit(false, 195, 3);  submit(false, 192, 4);  run(200, "secondary misses");
    if nb then
      tab := (0, 1, 2, 3, 12, others => 0);
      for i in 0 to 4 loop expect_i("T4 acc " & integer'image(i), rel_acc(i), tab(i)); end loop;
      tab := (12, 13, 14, 15, 13, others => 0);
      for i in 0 to 4 loop expect_i("T4 resp " & integer'image(i), rel_resp(i), tab(i)); end loop;
      expect_i("T4 primary misses", st_pri - p0, 1);  expect_i("T4 secondary misses", st_sec - s0, 3);  expect_i("T4 hits", st_hit - h0, 1);
    else
      tab := (0, 13, 14, 15, 16, others => 0);
      for i in 0 to 4 loop expect_i("T4 acc " & integer'image(i), rel_acc(i), tab(i)); end loop;
      tab := (12, 14, 15, 16, 17, others => 0);
      for i in 0 to 4 loop expect_i("T4 resp " & integer'image(i), rel_resp(i), tab(i)); end loop;
      expect_i("T4 primary misses", st_pri - p0, 1);  expect_i("T4 secondary misses", st_sec - s0, 0);  expect_i("T4 hits", st_hit - h0, 4);
    end if;

    -- ---- T5: a read miss must wait for buffered writes to its line ----
    if WBD >= 2 then
      clear;  submit(true, 230, 0);  submit(true, 21, 1);  submit(false, 21, 2);  run(200, "write buffer vs read");
      expect_i("T5 acc W0", rel_acc(0), 0);  expect_i("T5 acc W1", rel_acc(1), 1);  expect_i("T5 acc R", rel_acc(2), 2);
      expect_i("T5 read resp", rel_resp(2), 20);
    end if;

    -- ---- T6: a write to a line with a miss outstanding waits ----
    clear;  submit(false, 40, 0);  submit(true, 41, 1);  submit(false, 41, 14);  run(200, "write vs miss");
    expect_i("T6 W acc", rel_acc(1), 13);  expect_i("T6 R acc", rel_acc(2), 14);  expect_i("T6 R resp", rel_resp(2), 15);

    -- ---- T7: write burst ----
    if WBD = 0 or WBD = 1 or WBD = 2 or WBD = 4 then
      case WBD is
        when 0 => tab := (0, 4, 8, 12, 16, 20, 24, 28);
        when 1 => tab := (0, 2, 6, 10, 14, 18, 22, 26);
        when 2 => tab := (0, 1, 2, 6, 10, 14, 18, 22);
        when others => tab := (0, 1, 2, 3, 4, 6, 10, 14);
      end case;
      clear;  for i in 0 to 7 loop submit(true, 224 + 4 * i, 0); end loop;  run(300, "write burst");
      for i in 0 to 7 loop expect_i("T7 write " & integer'image(i) & " accepted", rel_acc(i), tab(i)); end loop;
    end if;

    -- ---- T8: a second write to the address of the entry that is being sent to memory right now must not be lost ----
    clear;  submit(true, 236, 0);  submit(true, 236, 1);  submit(false, 236, 40);  run(300, "write merge race");
    clear;  submit(true, 237, 0);  submit(true, 237, 1);  submit(true, 237, 2);  submit(false, 237, 40);  run(300, "write merge race 2");

    -- ---- random streams ----
    stream(35, 70, 300, t_a);
    stream(20, 10, 300, t_b);
    stream(75, 50, 300, t_c);
    errs <= nerr;  tot_a <= t_a;  tot_b <= t_b;  tot_c <= t_c;
    fin <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_nb_cache is
end entity;

architecture sim of tb_nb_cache is
  signal d0, d1, d2, d3, d4, d5 : std_logic;
  signal e0, e1, e2, e3, e4, e5, a0, b0, c0, a1, b1, c1, a2, b2, c2, a3, b3, c3, a4, b4, c4, a5, b5, c5 : natural;
begin
  hb : entity work.nbc_harness generic map (NM => 1, HUM => false, WBD => 4) port map (d0, e0, a0, b0, c0);    -- blocking
  hh : entity work.nbc_harness generic map (NM => 1, HUM => true,  WBD => 4) port map (d1, e1, a1, b1, c1);    -- hit under miss
  hm : entity work.nbc_harness generic map (NM => 4, HUM => true,  WBD => 4) port map (d2, e2, a2, b2, c2);    -- miss under miss, 4-entry write buffer
  w0 : entity work.nbc_harness generic map (NM => 4, HUM => true,  WBD => 0) port map (d3, e3, a3, b3, c3);    -- no write buffer
  w1 : entity work.nbc_harness generic map (NM => 4, HUM => true,  WBD => 1) port map (d4, e4, a4, b4, c4);
  w2 : entity work.nbc_harness generic map (NM => 4, HUM => true,  WBD => 2) port map (d5, e5, a5, b5, c5);

  process
    variable errors : integer;
  begin
    wait until d0 = '1' and d1 = '1' and d2 = '1' and d3 = '1' and d4 = '1' and d5 = '1';
    errors := e0 + e1 + e2 + e3 + e4 + e5;
    if not (a0 > a1 and a1 > a2) then errors := errors + 1; report "FAIL: hot stream totals not blocking > hit-under-miss > miss-under-miss" severity note; end if;
    if not (b0 > b1 and b1 >= b2) then errors := errors + 1; report "FAIL: wide stream totals" severity note; end if;
    if not (c3 > c4 and c4 >= c5 and c5 >= c2 and c3 > c2) then errors := errors + 1; report "FAIL: write-heavy totals not nonincreasing with buffer depth" severity note; end if;
    report "cycles for 300 requests, hot stream:        blocking " & integer'image(a0) & ", hit-under-miss " & integer'image(a1) & ", miss-under-miss " & integer'image(a2) severity note;
    report "cycles for 300 requests, wide stream:       blocking " & integer'image(b0) & ", hit-under-miss " & integer'image(b1) & ", miss-under-miss " & integer'image(b2) severity note;
    report "cycles for 300 requests, write-heavy stream: write buffer depth 0: " & integer'image(c3) & ", 1: " & integer'image(c4) & ", 2: " & integer'image(c5) & ", 4: " & integer'image(c2) severity note;
    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED: " & integer'image(errors) & " errors" severity error; end if;
    finish;
  end process;
end architecture;
