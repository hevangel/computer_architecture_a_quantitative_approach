-- Memory: MEM_LAT 10; a line write keeps the port busy 4 cycles (WR_OCC), a read 1.  Cycle numbers are relative to the first accepted request (cycle 0).
-- Hand-derived timeline of one miss on an idle cache (request accepted at cycle 0):
--   c1 fetch leaves for memory (the MSHR becomes visible at c1);  c11 the line returns;  c12 its first target is answered / patched;  one more target per cycle;
--   the cycle after the last target the line is INSTALLED (a dirty victim is pushed into the write-back buffer), the MSHR is free and the line is valid one cycle later.
--   So a read miss is answered at +12, and the MSHR is busy until the end of c13 for a single target.
-- Directed expectations ("acc" = cycle a request is accepted, "resp" = cycle its answer appears):
--   hit: +1.  clean-victim conflict miss: +12.
--   hit under miss: R0 miss @0, R1 hit @1 -> non-blocking acc 1 / resp 2; blocking: acc 14, resp 15 (the MSHR is busy until the end of c13)
--   miss under miss: two lines @0, @1 -> NM >= 2 resp 12, 13; one MSHR or blocking: second accepted @14, answered @26
--   four reads of one line @0..3 -> answers 12 13 14 15 (blocking: later reads hit: acc 14 15 16, resp 15 16 17); a fifth read @4 stalls until the line is installed:
--       the install is at c16, so it is accepted @17 and answered @18 (blocking: acc 17, resp 18)
--   store miss (write-allocate): W @0, R of the same word @1 -> the load is answered @13 with the STORE's value (targets run in program order); blocking: R acc 14, resp 15
--   dirty eviction: read of a conflicting line @0 is answered @12 (the write-back is off the critical path); at c13 the dirty victim goes to the write-back buffer, at c14 the
--       memory port takes it (busy c15..c17), so a read of the evicted line accepted @14 can fetch only at c18: answered @29 (= 14 + 15), and it returns the stored value
--   two dirty evictions back to back (WBD >= 2, NM >= 2): R(Z1) @0 evicts X1, R(Z2) @1 evicts X2; X1 is written back at c14 (busy to c17), X2 sits in the buffer from c15;
--       R(X2) @15 must NOT fetch at c18 (X2 is still in the buffer, a fetch would read stale memory): X2 is written at c18, the fetch leaves at c22, answered @33
--   stores that hit cause no memory traffic; evicting the dirty line later costs exactly one line write.
-- Then three random streams; every read must return the program-order value; after a FLUSH main memory must equal the shadow memory.

-- One harness entity per configuration (one process owns all state); the top compares the numbers the harnesses report.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wbc_harness is
  generic (NM : positive := 4; HUM : boolean := true; WBD : positive := 2);
  port (fin : out std_logic; errs : out natural; tot_a, tot_b, tot_c, lw_a, st_a : out natural);
end entity;

architecture sim of wbc_harness is
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal req_valid, req_write, flush : std_logic := '0';
  signal req_addr : natural range 0 to 255 := 0;
  signal req_wdata : std_logic_vector(31 downto 0) := (others => '0');
  signal req_id : natural range 0 to 63 := 0;
  signal req_ready, hit_valid, fill_valid, mem_valid, mem_write, mem_ready, mem_rvalid, violation, flush_done : std_logic;
  signal hit_id, fill_id : natural range 0 to 63;
  signal hit_data, fill_data, dbg_data : std_logic_vector(31 downto 0);
  signal mem_wdata, mem_rline : std_logic_vector(127 downto 0);
  signal mem_addr : natural range 0 to 255;
  signal mem_tag, mem_rtag : natural range 0 to 3;
  signal st_hit, st_pri, st_sec, st_wb, n_lwr : natural;
  signal dbg_addr : natural range 0 to 255 := 0;
begin
  clk <= not clk after 5 ns;

  dut : entity work.wb_cache
    generic map (NM => NM, HUM => HUM, WBD => WBD)
    port map (clk => clk, rst_n => rst_n, req_valid => req_valid, req_write => req_write, req_addr => req_addr, req_wdata => req_wdata, req_id => req_id,
              req_ready => req_ready, hit_valid => hit_valid, hit_id => hit_id, hit_data => hit_data, fill_valid => fill_valid, fill_id => fill_id,
              fill_data => fill_data, flush => flush, flush_done => flush_done, mem_valid => mem_valid, mem_write => mem_write, mem_addr => mem_addr,
              mem_wdata => mem_wdata, mem_tag => mem_tag, mem_ready => mem_ready, mem_rvalid => mem_rvalid, mem_rtag => mem_rtag, mem_rline => mem_rline,
              stat_hit => st_hit, stat_pri => st_pri, stat_sec => st_sec, stat_wb => st_wb);
  mem : entity work.wb_mem
    port map (clk => clk, rst_n => rst_n, mem_valid => mem_valid, mem_write => mem_write, mem_addr => mem_addr, mem_wdata => mem_wdata, mem_tag => mem_tag,
              mem_ready => mem_ready, mem_rvalid => mem_rvalid, mem_rtag => mem_rtag, mem_rline => mem_rline, dbg_addr => dbg_addr, dbg_data => dbg_data,
              violation => violation, n_lwr => n_lwr);

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
    variable p0, s0, h0, w0, dummy : integer;
    variable nb, multi : boolean;
    variable tab : int_arr(0 to 7);
    variable t_a, t_b, t_c, l_a, s_a : integer := 0;

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
      idle(60);
    end procedure;
    procedure expect_i(what : string; got, exp_v : integer) is
    begin
      if got /= exp_v then nerr := nerr + 1; report "FAIL " & what & ": got " & integer'image(got) & " expected " & integer'image(exp_v) severity note; end if;
    end procedure;
    impure function rel_acc(i : integer) return integer is begin return acc_c(i) - acc_c(0); end function;
    impure function rel_resp(i : integer) return integer is begin return resp_c(i) - acc_c(0); end function;

    -- flush the cache and compare main memory with the shadow memory
    procedure flush_and_check(what : string) is
      variable t : integer := 0;
    begin
      flush <= '1';
      neg;
      while flush_done /= '1' and t < 2000 loop neg; t := t + 1; end loop;
      if flush_done /= '1' then nerr := nerr + 1; report "FAIL [" & what & "] flush never finished" severity note; end if;
      neg;  flush <= '0';  idle(5);
      for a in 0 to 255 loop
        dbg_addr <= a;  wait for 1 ns;
        if unsigned(dbg_data) /= shadow(a) then
          nerr := nerr + 1;  if nerr < 5 then report "FAIL [" & what & "] main memory word " & integer'image(a) & " wrong" severity note; end if;
        end if;
      end loop;
    end procedure;

    procedure stream(wr_pct, hot_pct, hot_size, n : integer; total, stores : out integer) is
      variable rw, rh, ahot, awide, gap, tc, last, ad : integer;
    begin
      clear;  tc := 0;  stores := 0;
      for i in 0 to n - 1 loop
        rw := rnd(100);  rh := rnd(100);  ahot := rnd(hot_size);  awide := rnd(256);  gap := rnd(3);
        tc := tc + gap;
        if rh < hot_pct then ad := ahot; else ad := awide; end if;
        submit(rw < wr_pct, ad, tc);
        if rw < wr_pct then stores := stores + 1; end if;
      end loop;
      run(20000, "stream");
      last := 0;
      for i in 0 to n - 1 loop
        if acc_c(i) > last then last := acc_c(i); end if;
        if resp_c(i) > last then last := resp_c(i); end if;
      end loop;
      total := last - acc_c(0);
      idle(100);
      flush_and_check("stream");
    end procedure;
  begin
    fin <= '0';  errs <= 0;  tot_a <= 0;  tot_b <= 0;  tot_c <= 0;  lw_a <= 0;  st_a <= 0;
    for a in 0 to 255 loop shadow(a) := x"5A000000" + to_unsigned(a * 17, 32); end loop;
    nb := HUM;  multi := HUM and NM >= 2;
    for i in 1 to 3 loop neg; end loop;
    rst_n <= '1';
    for i in 1 to 8 loop neg; end loop;

    -- ---- T1 ----
    clear;  submit(false, 36, 0);   run(100, "miss");     expect_i("read miss latency", rel_resp(0), 12);
    clear;  submit(false, 37, 0);   run(100, "hit");      expect_i("read hit latency", rel_resp(0), 1);
    clear;  submit(false, 100, 0);  run(100, "conflict"); expect_i("clean conflict miss latency", rel_resp(0), 12);
    -- ---- T2: hit under miss ----
    clear;  submit(false, 8, 0);  run(100, "preload");
    clear;  submit(false, 68, 0);  submit(false, 9, 1);  run(200, "hit under miss");
    expect_i("T2 miss resp", rel_resp(0), 12);
    if nb then expect_i("T2 hit acc", rel_acc(1), 1);  expect_i("T2 hit resp", rel_resp(1), 2);
    else       expect_i("T2 hit acc", rel_acc(1), 14); expect_i("T2 hit resp", rel_resp(1), 15); end if;
    -- ---- T3: miss under miss ----
    clear;  submit(false, 160, 0);  submit(false, 172, 1);  run(200, "miss under miss");
    expect_i("T3 first resp", rel_resp(0), 12);
    if multi then expect_i("T3 second acc", rel_acc(1), 1);  expect_i("T3 second resp", rel_resp(1), 13);
    else          expect_i("T3 second acc", rel_acc(1), 14); expect_i("T3 second resp", rel_resp(1), 26); end if;
    -- ---- T4: secondary misses ----
    p0 := st_pri;  s0 := st_sec;  h0 := st_hit;
    clear;  submit(false, 192, 0);  submit(false, 193, 1);  submit(false, 194, 2);  submit(false, 195, 3);  submit(false, 192, 4);  run(200, "secondary misses");
    if nb then
      tab := (0, 1, 2, 3, 17, others => 0);
      for i in 0 to 4 loop expect_i("T4 acc " & integer'image(i), rel_acc(i), tab(i)); end loop;
      tab := (12, 13, 14, 15, 18, others => 0);
      for i in 0 to 4 loop expect_i("T4 resp " & integer'image(i), rel_resp(i), tab(i)); end loop;
      expect_i("T4 primary misses", st_pri - p0, 1);  expect_i("T4 secondary misses", st_sec - s0, 3);  expect_i("T4 hits", st_hit - h0, 1);
    else
      tab := (0, 14, 15, 16, 17, others => 0);
      for i in 0 to 4 loop expect_i("T4 acc " & integer'image(i), rel_acc(i), tab(i)); end loop;
      tab := (12, 15, 16, 17, 18, others => 0);
      for i in 0 to 4 loop expect_i("T4 resp " & integer'image(i), rel_resp(i), tab(i)); end loop;
      expect_i("T4 primary misses", st_pri - p0, 1);  expect_i("T4 secondary misses", st_sec - s0, 0);  expect_i("T4 hits", st_hit - h0, 4);
    end if;
    -- ---- T5: store miss = write-allocate; the load behind it sees the store ----
    clear;  submit(true, 200, 0);  submit(false, 200, 1);  run(200, "store miss");
    expect_i("T5 store acc", rel_acc(0), 0);
    if nb then expect_i("T5 load acc", rel_acc(1), 1);  expect_i("T5 load resp", rel_resp(1), 13);
    else       expect_i("T5 load acc", rel_acc(1), 14); expect_i("T5 load resp", rel_resp(1), 15); end if;
    -- ---- T6: dirty eviction is off the critical path; the evicted line comes back with the stored value ----
    w0 := n_lwr;
    clear;  submit(false, 8, 0);  submit(false, 200, 14);  run(300, "dirty eviction");
    expect_i("T6 evicting read resp", rel_resp(0), 12);
    expect_i("T6 re-read acc", rel_acc(1), 14);
    expect_i("T6 re-read resp", rel_resp(1), 29);
    expect_i("T6 line writes", n_lwr - w0, 1);
    -- ---- T6b: two dirty evictions; the second victim is re-read while it is still in the write-back buffer ----
    if multi and WBD >= 2 then
      clear;  submit(true, 240, 0);  submit(true, 244, 0);  run(200, "dirty setup");
      clear;  submit(false, 16, 0);  submit(false, 20, 1);  submit(false, 244, 15);  run(300, "two dirty evictions");
      expect_i("T6b first resp", rel_resp(0), 12);
      expect_i("T6b second resp", rel_resp(1), 13);
      expect_i("T6b re-read acc", rel_acc(2), 15);
      expect_i("T6b re-read resp", rel_resp(2), 33);
    end if;
    -- ---- T7: stores that hit cost no memory traffic; the dirty line is written back once, when evicted ----
    clear;  submit(false, 16, 0);  run(100, "make 16 resident");
    w0 := n_lwr;  h0 := st_hit;
    clear;  for i in 0 to 3 loop submit(true, 16 + i, i); end loop;  run(100, "store hits");
    for i in 0 to 3 loop expect_i("T7 store " & integer'image(i) & " acc", rel_acc(i), i); end loop;
    expect_i("T7 store hits counted", st_hit - h0, 4);
    expect_i("T7 no line writes yet", n_lwr - w0, 0);
    clear;  submit(false, 240, 0);  run(200, "evict the dirty line");
    expect_i("T7 one line write for four stores", n_lwr - w0, 1);
    expect_i("T7 evicting read resp", rel_resp(0), 12);

    -- ---- random streams ----
    flush_and_check("directed tests");
    w0 := n_lwr;  stream(40, 90, 24, 300, t_a, s_a);  l_a := n_lwr - w0;
    stream(20, 10, 64, 300, t_b, dummy);
    stream(70, 50, 64, 300, t_c, dummy);
    errs <= nerr;  tot_a <= t_a;  tot_b <= t_b;  tot_c <= t_c;  lw_a <= l_a;  st_a <= s_a;
    fin <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_wb_cache is
end entity;

architecture sim of tb_wb_cache is
  signal d0, d1, d2, d3, d4 : std_logic;
  signal e0, e1, e2, e3, e4, a0, b0, c0, l0, s0, a1, b1, c1, l1, s1, a2, b2, c2, l2, s2, a3, b3, c3, l3, s3, a4, b4, c4, l4, s4 : natural;
begin
  hb : entity work.wbc_harness generic map (NM => 1, HUM => false, WBD => 2) port map (d0, e0, a0, b0, c0, l0, s0);   -- blocking
  hh : entity work.wbc_harness generic map (NM => 1, HUM => true,  WBD => 2) port map (d1, e1, a1, b1, c1, l1, s1);   -- hit under miss
  hm : entity work.wbc_harness generic map (NM => 4, HUM => true,  WBD => 2) port map (d2, e2, a2, b2, c2, l2, s2);   -- miss under miss
  w1 : entity work.wbc_harness generic map (NM => 4, HUM => true,  WBD => 1) port map (d3, e3, a3, b3, c3, l3, s3);   -- one write-back entry
  w4 : entity work.wbc_harness generic map (NM => 4, HUM => true,  WBD => 4) port map (d4, e4, a4, b4, c4, l4, s4);   -- four write-back entries

  process
    variable errors : integer;
  begin
    wait until d0 = '1' and d1 = '1' and d2 = '1' and d3 = '1' and d4 = '1';
    errors := e0 + e1 + e2 + e3 + e4;
    if not (b0 > b1 and b1 > b2) then errors := errors + 1; report "FAIL: wide stream totals not blocking > hit-under-miss > miss-under-miss" severity note; end if;
    if not (c0 > c1 and c1 > c2) then errors := errors + 1; report "FAIL: write-heavy stream totals" severity note; end if;
    if not (c3 >= c2 and c2 >= c4) then errors := errors + 1; report "FAIL: totals not nonincreasing with write-back buffer depth" severity note; end if;
    if not (l2 * 3 < s2) then errors := errors + 1; report "FAIL: write-back did not cut memory writes" severity note; end if;
    report "wide stream, 300 requests:        blocking " & integer'image(b0) & ", hit-under-miss " & integer'image(b1) & ", miss-under-miss " & integer'image(b2) & " cycles" severity note;
    report "write-heavy stream, 300 requests: blocking " & integer'image(c0) & ", hit-under-miss " & integer'image(c1) & ", miss-under-miss " & integer'image(c2) &
           " cycles;  write-back buffer of 1/2/4 lines: " & integer'image(c3) & "/" & integer'image(c2) & "/" & integer'image(c4) severity note;
    report "hot stream: " & integer'image(s2) & " stores became " & integer'image(l2) & " line writes in memory (write-through would need " & integer'image(s2) & " word writes)" severity note;
    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED: " & integer'image(errors) & " errors" severity error; end if;
    finish;
  end process;
end architecture;
