-- Self-checking testbench for dram_ctrl + dram_device (same tests, same expected numbers as the SystemVerilog testbench).
-- Timing parameters (cycles): tRCD 3, tCL 3, tCWL 2, tRP 3, tRAS 7, tWR 3, tRTP 2, tRRD 2, tCCD = BL = 4, tWTR 3, tRTW 6, tRFC 12.
-- Hand-derived expectations, request accepted at cycle q on an otherwise idle system:
--     row miss 2 + tRCD + tCL + BL = 12;  row hit 2 + tCL + BL = 9;  row conflict 2 + tRP + tRCD + tCL + BL = 15
--     closed-page policy: all three are 12.
--     FR-FCFS on A0 B0 A1 B1 A2 B2 A3 B3 (rows of ONE bank): 2 activations;  FCFS: 8.
--     64 sequential bursts, bank-interleaved: exactly q + 264 cycles (data bus kept busy).
-- Every run also demands: read data equals the program-order value, no request lost, zero violations from the device's timing checker.
--
-- VHDL cannot call procedures of another entity, so each configuration is a harness ENTITY with ONE process that owns all state and
-- runs the scenario chosen by a generic; the top compares the numbers the harnesses report.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dram_harness is
  generic (SCEN : natural := 0;          -- 0..2: latency + A/B pattern (2 only with FCFS) + random streams;  3: streaming;  4: refresh window
           FR_FCFS : boolean := true; OPEN_PAGE : boolean := true; REFI : natural := 400);
  port (fin : out std_logic; errs : out natural; ab_acts : out natural; ab_time : out natural; row_total : out natural);
end entity;

architecture sim of dram_harness is
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal req_valid, req_write : std_logic := '0';
  signal req_addr  : std_logic_vector(7 downto 0) := (others => '0');
  signal req_wdata : std_logic_vector(127 downto 0) := (others => '0');
  signal req_id    : natural range 0 to 63 := 0;
  signal req_ready, rd_resp_valid, wr_resp_valid, cmd_valid, dev_rd_valid, violation : std_logic;
  signal rd_resp_id, wr_resp_id : natural range 0 to 63;
  signal rd_resp_data, cmd_wdata, dev_rd_data : std_logic_vector(127 downto 0);
  signal cmd : natural range 0 to 7;
  signal cmd_bank : natural range 0 to 3;
  signal cmd_row  : natural range 0 to 15;
  signal cmd_col  : natural range 0 to 3;
  signal st_act, st_pre, st_rd, st_wr, st_ref, dev_refs, max_gap : natural;
begin
  clk <= not clk after 5 ns;

  ctrl : entity work.dram_ctrl
    generic map (FR_FCFS => FR_FCFS, OPEN_PAGE => OPEN_PAGE, tREFI => REFI)
    port map (clk => clk, rst_n => rst_n, req_valid => req_valid, req_ready => req_ready, req_write => req_write, req_addr => req_addr,
              req_wdata => req_wdata, req_id => req_id, rd_resp_valid => rd_resp_valid, rd_resp_id => rd_resp_id, rd_resp_data => rd_resp_data,
              wr_resp_valid => wr_resp_valid, wr_resp_id => wr_resp_id, cmd_valid => cmd_valid, cmd => cmd, cmd_bank => cmd_bank,
              cmd_row => cmd_row, cmd_col => cmd_col, cmd_wdata => cmd_wdata, dev_rd_valid => dev_rd_valid, dev_rd_data => dev_rd_data,
              stat_act => st_act, stat_pre => st_pre, stat_rd => st_rd, stat_wr => st_wr, stat_ref => st_ref);
  dev : entity work.dram_device
    port map (clk => clk, rst_n => rst_n, cmd_valid => cmd_valid, cmd => cmd, cmd_bank => cmd_bank, cmd_row => cmd_row, cmd_col => cmd_col,
              cmd_wdata => cmd_wdata, rd_valid => dev_rd_valid, rd_data => dev_rd_data, violation => violation, stat_refs => dev_refs,
              max_ref_gap => max_gap);

  main : process
    constant MAXR : natural := 1024;
    subtype burst_t is std_logic_vector(127 downto 0);
    type int_arr   is array (natural range <>) of integer;
    type burst_arr is array (natural range <>) of burst_t;
    type bool_arr  is array (natural range <>) of boolean;
    variable r_write : bool_arr(0 to MAXR-1);
    variable r_addr, r_time, enq, done_at : int_arr(0 to MAXR-1);
    variable r_wdata, r_exp : burst_arr(0 to MAXR-1);
    variable id_req : int_arr(0 to 63);
    variable shadow : burst_arr(0 to 255);
    variable s_w : bool_arr(0 to 299);
    variable s_a, s_g : int_arr(0 to 299);
    variable n_req, ptr, completed, cyc, nerr : integer := 0;
    variable wseed : unsigned(31 downto 0) := to_unsigned(77, 32);
    variable seed  : unsigned(31 downto 0) := to_unsigned(2013, 32);
    variable last_avg100, last_total : integer := 0;
    variable a0, tmax, nrefs, tstream, r0, c0, bw100 : integer;
    variable w : boolean;
    variable ad : integer;
    variable lat_miss, lat_hit, lat_conf : integer;

    function init_burst(a : natural) return burst_t is
      variable r : burst_t;
    begin
      for k in 0 to 3 loop
        r(32*k + 31 downto 32*k) := std_logic_vector(unsigned'(x"D0000000") or shift_left(to_unsigned(a, 32), 8) or to_unsigned(k, 32));
      end loop;
      return r;
    end function;

    function fmt2(v : integer) return string is
    begin
      if (v mod 100) < 10 then return integer'image(v / 100) & ".0" & integer'image(v mod 100); end if;
      return integer'image(v / 100) & "." & integer'image(v mod 100);
    end function;

    impure function rnd(n : positive) return integer is
    begin
      seed := resize(seed * to_unsigned(1664525, 32), 32) + to_unsigned(1013904223, 32);
      return to_integer(seed(30 downto 16)) mod n;
    end function;

    -- one falling clock edge: drive the next due request, watch the responses
    procedure tick is
      variable k : integer;
    begin
      wait until falling_edge(clk);
      if rst_n = '1' then
        req_valid <= '0';
        if ptr < n_req and cyc >= r_time(ptr) and req_ready = '1' then
          req_valid <= '1';
          if r_write(ptr) then req_write <= '1'; else req_write <= '0'; end if;
          req_addr  <= std_logic_vector(to_unsigned(r_addr(ptr), 8));
          req_wdata <= r_wdata(ptr);
          req_id    <= ptr mod 64;
          id_req(ptr mod 64) := ptr;  enq(ptr) := cyc;  ptr := ptr + 1;
        end if;
        if rd_resp_valid = '1' then
          k := id_req(rd_resp_id);  done_at(k) := cyc;  completed := completed + 1;
          if rd_resp_data /= r_exp(k) then
            nerr := nerr + 1;  report "FAIL read of request " & integer'image(k) & " (addr " & integer'image(r_addr(k)) & ")" severity note;
          end if;
        end if;
        if wr_resp_valid = '1' then
          k := id_req(wr_resp_id);  done_at(k) := cyc;  completed := completed + 1;
        end if;
        if violation = '1' and nerr = 0 then
          nerr := nerr + 1;  report "FAIL: the DRAM device reported a timing/protocol violation" severity note;
        end if;
      end if;
      cyc := cyc + 1;
    end procedure;

    procedure clear is begin n_req := 0; ptr := 0; completed := 0; end procedure;

    -- queue a request `t` cycles from now; write data is pseudo-random; the expected read value is the program-order value
    procedure submit(wr : boolean; addr : integer; t : integer) is
      variable wd : burst_t;
    begin
      for k in 0 to 3 loop
        wseed := resize(wseed * to_unsigned(1664525, 32), 32) + to_unsigned(1013904223, 32);
        wd(32*k + 31 downto 32*k) := std_logic_vector(wseed);
      end loop;
      r_write(n_req) := wr;  r_addr(n_req) := addr;  r_time(n_req) := cyc + 2 + t;  r_wdata(n_req) := wd;
      r_exp(n_req) := shadow(addr);
      if wr then shadow(addr) := wd; end if;
      n_req := n_req + 1;
    end procedure;

    procedure run(timeout : integer; what : string) is
      variable t : integer := 0;
    begin
      while completed < n_req and t < timeout loop tick; t := t + 1; end loop;
      if completed < n_req then
        nerr := nerr + 1;
        report "FAIL [" & what & "] " & integer'image(completed) & " of " & integer'image(n_req) & " requests completed in " & integer'image(timeout) & " cycles" severity note;
      end if;
      for i in 1 to 4 loop tick; end loop;
    end procedure;

    procedure idle(n : integer) is begin for i in 1 to n loop tick; end loop; end procedure;
    impure function latency(i : integer) return integer is begin return done_at(i) - enq(i); end function;

    procedure expect_i(what : string; got, exp_v : integer) is
    begin
      if got /= exp_v then
        nerr := nerr + 1;  report "FAIL " & what & ": got " & integer'image(got) & " expected " & integer'image(exp_v) severity note;
      end if;
    end procedure;

    procedure make_stream(kind : integer) is   -- 0: small hot set   1: wide random   2: high row locality
      variable prev : integer := 0;
      variable r1, r2 : integer;
    begin
      for i in 0 to 299 loop
        r1 := rnd(10);  s_w(i) := (r1 < 4);
        s_g(i) := rnd(5);
        if kind = 0 then s_a(i) := rnd(24);
        elsif kind = 1 then s_a(i) := rnd(256);
        else
          r1 := rnd(10);
          if r1 < 8 then r2 := rnd(4); s_a(i) := (prev - (prev mod 4)) + r2; else s_a(i) := rnd(256); end if;
        end if;
        prev := s_a(i);
      end loop;
    end procedure;

    procedure run_stream(what : string; n : integer) is
      variable tc, sum, mx : integer;
    begin
      clear;  tc := 0;
      for i in 0 to n-1 loop tc := tc + s_g(i); submit(s_w(i), s_a(i), tc); end loop;
      run(30000, what);
      sum := 0;  mx := 0;
      for i in 0 to n-1 loop
        sum := sum + latency(i);
        if done_at(i) > mx then mx := done_at(i); end if;
      end loop;
      last_avg100 := sum * 100 / n;  last_total := mx - enq(0);
    end procedure;

    procedure ab_pattern is
      variable t : integer;
    begin
      a0 := st_act;  clear;
      for i in 0 to 3 loop submit(false, 48 + i, 2 * i); submit(false, 144 + i, 2 * i + 1); end loop;
      run(1000, "A/B pattern");
      ab_acts <= st_act - a0;
      tmax := 0;  for i in 0 to 7 loop if done_at(i) > tmax then tmax := done_at(i); end if; end loop;
      ab_time <= tmax - enq(0);
      if FR_FCFS then expect_i("FR-FCFS: row activations for A0 B0 A1 B1 ...", st_act - a0, 2);
      else            expect_i("FCFS: row activations for A0 B0 A1 B1 ...", st_act - a0, 8); end if;
      report "A/B pattern: " & integer'image(st_act - a0) & " activations in " & integer'image(tmax - enq(0)) & " cycles" severity note;
    end procedure;
  begin
    fin <= '0';  errs <= 0;  ab_acts <= 0;  ab_time <= 0;  row_total <= 0;
    for a in 0 to 255 loop shadow(a) := init_burst(a); end loop;
    for i in 1 to 3 loop tick; end loop;
    rst_n <= '1';
    for i in 1 to 5 loop tick; end loop;

    if SCEN <= 2 then
      -- ---- latencies on an idle system ({row 2, bank 1, col 0} = 36, same row col 1 = 37, {row 5, bank 1} = 84) ----
      lat_miss := 12;
      if OPEN_PAGE then lat_hit := 9; lat_conf := 15; else lat_hit := 12; lat_conf := 12; end if;
      clear;  submit(false, 36, 0);  run(100, "miss");      expect_i("row miss",     latency(0), lat_miss);  idle(30);
      clear;  submit(false, 37, 0);  run(100, "hit");       expect_i("row hit",      latency(0), lat_hit);   idle(30);
      clear;  submit(false, 84, 0);  run(100, "conflict");  expect_i("row conflict", latency(0), lat_conf);
      report "latency: miss " & integer'image(lat_miss) & " / hit " & integer'image(lat_hit) & " / conflict " & integer'image(lat_conf) & " cycles" severity note;

      -- ---- FR-FCFS vs FCFS (the open-page FR-FCFS and the FCFS harnesses) ----
      if OPEN_PAGE then ab_pattern; end if;

      -- ---- data integrity and policy comparison on random streams ----
      make_stream(0);  run_stream("hot set", 300);
      report "hot set (same-address hazards): average latency " & fmt2(last_avg100) severity note;
      make_stream(1);  run_stream("wide random", 300);
      report "wide random: average latency " & fmt2(last_avg100) & " (total " & integer'image(last_total) & " cycles)" severity note;
      make_stream(2);  run_stream("row locality", 300);
      report "row locality: average latency " & fmt2(last_avg100) & " (total " & integer'image(last_total) & " cycles)" severity note;
      row_total <= last_total;

    elsif SCEN = 3 then
      -- ---- streaming: 64 sequential bursts keep the data bus busy ----
      clear;  for i in 0 to 63 loop submit(false, i, 0); end loop;
      run(2000, "streaming");
      tmax := 0;  for i in 0 to 63 loop if done_at(i) > tmax then tmax := done_at(i); end if; end loop;
      tstream := tmax - enq(0);
      expect_i("streaming: 64 bursts finish exactly q + 264 cycles", tstream, 264);
      expect_i("streaming: activations (4 banks x 4 rows)", st_act, 16);
      expect_i("streaming: reads", st_rd, 64);
      bw100 := 64 * 4 * 100 / tstream;
      report "streaming: 64 bursts in " & integer'image(tstream) & " cycles = " & integer'image(bw100) & "% of peak data-bus bandwidth" severity note;

    else
      -- ---- refresh every 100 cycles; advance the random generator past the three streams exactly as the SystemVerilog top does ----
      make_stream(0);  make_stream(1);  make_stream(2);
      r0 := dev_refs;  c0 := cyc;
      clear;
      for i in 0 to 49 loop
        w := (rnd(10) < 4);  ad := rnd(256);
        submit(w, ad, 12 * i);
      end loop;
      run(2000, "refresh traffic");
      while cyc < c0 + 720 loop tick; end loop;
      nrefs := dev_refs - r0;
      if nrefs < 5 or nrefs > 8 then
        nerr := nerr + 1;  report "FAIL: " & integer'image(nrefs) & " refreshes in a 720-cycle window with tREFI = 100 (expected 5..8)" severity note;
      end if;
      expect_i("controller and device agree on the refresh count", st_ref, dev_refs);
      if max_gap > 140 then
        nerr := nerr + 1;  report "FAIL: refresh gap " & integer'image(max_gap) & " cycles exceeds tREFI + 40" severity note;
      end if;
      report "refresh: " & integer'image(nrefs) & " REF commands in a 720-cycle window (tREFI = 100); longest gap " & integer'image(max_gap) severity note;
    end if;

    errs <= nerr;
    fin <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_dram_controller is
end entity;

architecture sim of tb_dram_controller is
  signal fo, fc, ff, fs, fr : std_logic;
  signal eo, ec, ef, es, er : natural;
  signal ab_o, ab_f, abt_o, abt_f, tot_o, tot_f : natural;
begin
  ho : entity work.dram_harness generic map (SCEN => 0, FR_FCFS => true,  OPEN_PAGE => true,  REFI => 400)       -- FR-FCFS, open page
       port map (fin => fo, errs => eo, ab_acts => ab_o, ab_time => abt_o, row_total => tot_o);
  hc : entity work.dram_harness generic map (SCEN => 1, FR_FCFS => true,  OPEN_PAGE => false, REFI => 400)       -- FR-FCFS, closed page
       port map (fin => fc, errs => ec, ab_acts => open, ab_time => open, row_total => open);
  hf : entity work.dram_harness generic map (SCEN => 2, FR_FCFS => false, OPEN_PAGE => true,  REFI => 400)       -- FCFS, open page
       port map (fin => ff, errs => ef, ab_acts => ab_f, ab_time => abt_f, row_total => tot_f);
  hs : entity work.dram_harness generic map (SCEN => 3, FR_FCFS => true,  OPEN_PAGE => true,  REFI => 400)       -- streaming
       port map (fin => fs, errs => es, ab_acts => open, ab_time => open, row_total => open);
  hr : entity work.dram_harness generic map (SCEN => 4, FR_FCFS => true,  OPEN_PAGE => true,  REFI => 100)       -- refresh every 100 cycles
       port map (fin => fr, errs => er, ab_acts => open, ab_time => open, row_total => open);

  process
    variable errors : integer := 0;
  begin
    wait until fo = '1' and fc = '1' and ff = '1' and fs = '1' and fr = '1';
    errors := eo + ec + ef + es + er;
    if not (abt_o < abt_f) then
      errors := errors + 1;  report "FAIL: FR-FCFS (" & integer'image(abt_o) & " cycles) is not faster than FCFS (" & integer'image(abt_f) & ")" severity note;
    end if;
    if tot_o > tot_f then
      errors := errors + 1;  report "FAIL: FR-FCFS is slower than FCFS on the row-locality stream" severity note;
    end if;
    report "A/B pattern: FR-FCFS " & integer'image(ab_o) & " activations in " & integer'image(abt_o) & " cycles;  FCFS " & integer'image(ab_f) & " activations in " & integer'image(abt_f) & " cycles" severity note;
    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED: " & integer'image(errors) & " errors" severity error; end if;
    finish;
  end process;
end architecture;
