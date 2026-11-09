-- Single core (no contention): every access after the first iteration hits, so the totals follow from the operation costs (hit = 1 cycle, miss = BUS_LAT cycles, think NT between iterations):
--   TAS    : first iteration  xchg miss + load-counter miss + work + store-counter upgrade + release hit = 3 BUS_LAT + CS_LEN + 1;   later iterations 1 + 1 + CS_LEN + 1 + 1 = 4 + CS_LEN
--            => cycles = 3 BUS_LAT + CS_LEN + 1 + (N-1) (4 + CS_LEN + NT);   bus transactions: 1 BusRd + 2 BusRdX, independent of N
--   TTAS   : first iteration  load-L miss + xchg upgrade + load-counter miss + work + store-counter upgrade + release hit = 4 BUS_LAT + CS_LEN + 1;   later 5 + CS_LEN
--            => cycles = 4 BUS_LAT + CS_LEN + 1 + (N-1) (5 + CS_LEN + NT);   2 BusRd + 2 BusRdX
--   TICKET : first iteration  fetch-add miss + load-serving miss + load-counter miss + work + store-counter upgrade + release upgrade = 5 BUS_LAT + CS_LEN;   later 5 + CS_LEN
--            => cycles = 5 BUS_LAT + CS_LEN + (N-1) (5 + CS_LEN + NT);   2 BusRd + 3 BusRdX
-- With several cores the testbench checks what any correct lock must give: the counter equals P*N (no lost update), never more than one core inside the critical section, every core finishes
-- N iterations, and for the ticket lock the cores acquire in exactly the order they drew their tickets (FIFO).  The control without a lock must lose updates and overlap.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity lock_harness is
  generic (P : positive := 4; N : positive := 4; LOCK : natural := 0; BUS_LAT : positive := 4; CS_LEN : natural := 2; NT : natural := 3);
  port (fin : out std_logic; errors, cycles, rd, rdx, ctr, maxcs, total_acq : out natural);
end entity;

architecture sim of lock_harness is
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal done : std_logic;
  signal stat_rd, stat_rdx, stat_cycles, counter, cs_count : natural;
  signal acq_pulse, tick_pulse : std_logic_vector(P-1 downto 0);
begin
  clk <= not clk after 5 ns;
  dut : entity work.spinlock_bench
    generic map (P => P, N => N, LOCK => LOCK, BUS_LAT => BUS_LAT, CS_LEN => CS_LEN, NT => NT)
    port map (clk => clk, rst_n => rst_n, done => done, stat_rd => stat_rd, stat_rdx => stat_rdx, stat_cycles => stat_cycles, counter => counter,
              cs_count => cs_count, acq_pulse => acq_pulse, tick_pulse => tick_pulse);

  main : process
    type int_arr is array (natural range <>) of integer;
    variable acq_n : int_arr(0 to P-1) := (others => 0);
    variable tick_log, acq_log : int_arr(0 to 4095) := (others => 0);
    variable n_tick, n_acq, mx, t, nerr : integer := 0;
  begin
    fin <= '0';  errors <= 0;  cycles <= 0;  rd <= 0;  rdx <= 0;  ctr <= 0;  maxcs <= 0;  total_acq <= 0;
    wait until falling_edge(clk);  wait until falling_edge(clk);  wait until falling_edge(clk);  rst_n <= '1';
    t := 0;
    while done = '0' and t < 200000 loop
      wait until rising_edge(clk);
      if cs_count > mx then mx := cs_count; end if;
      for k in 0 to P-1 loop
        if tick_pulse(k) = '1' then tick_log(n_tick) := k; n_tick := n_tick + 1; end if;
        if acq_pulse(k) = '1' then acq_log(n_acq) := k; n_acq := n_acq + 1; acq_n(k) := acq_n(k) + 1; end if;
      end loop;
      t := t + 1;
    end loop;
    for i in 1 to 3 loop
      wait until rising_edge(clk);
      for k in 0 to P-1 loop
        if tick_pulse(k) = '1' then tick_log(n_tick) := k; n_tick := n_tick + 1; end if;
        if acq_pulse(k) = '1' then acq_log(n_acq) := k; n_acq := n_acq + 1; acq_n(k) := acq_n(k) + 1; end if;
      end loop;
    end loop;
    if done = '0' then nerr := nerr + 1; report "FAIL [P=" & integer'image(P) & " lock=" & integer'image(LOCK) & "] not finished after " & integer'image(t) & " cycles" severity note; end if;
    cycles <= stat_cycles;  rd <= stat_rd;  rdx <= stat_rdx;  ctr <= counter;  maxcs <= mx;  total_acq <= n_acq;
    if LOCK /= 3 then
      if counter /= P * N then nerr := nerr + 1; report "FAIL [P=" & integer'image(P) & " lock=" & integer'image(LOCK) & "] counter " & integer'image(counter) & ", expected " & integer'image(P * N) & " (lost updates)" severity note; end if;
      if mx > 1 then nerr := nerr + 1; report "FAIL [P=" & integer'image(P) & " lock=" & integer'image(LOCK) & "] " & integer'image(mx) & " cores inside the critical section at once" severity note; end if;
      for k in 0 to P-1 loop
        if acq_n(k) /= N then nerr := nerr + 1; report "FAIL [P=" & integer'image(P) & " lock=" & integer'image(LOCK) & "] core " & integer'image(k) & " acquired " & integer'image(acq_n(k)) & " times, expected " & integer'image(N) severity note; end if;
      end loop;
      if LOCK = 2 then
        if n_tick /= P * N or n_acq /= P * N then nerr := nerr + 1; report "FAIL ticket lock: " & integer'image(n_tick) & " tickets, " & integer'image(n_acq) & " acquisitions" severity note; end if;
        for i in 0 to n_acq - 1 loop
          if i < n_tick and acq_log(i) /= tick_log(i) then
            nerr := nerr + 1;  report "FAIL ticket lock not FIFO: acquisition " & integer'image(i) & " by core " & integer'image(acq_log(i)) & ", ticket " & integer'image(i) & " was drawn by core " & integer'image(tick_log(i)) severity note;
            exit;
          end if;
        end loop;
      end if;
    end if;
    errors <= nerr;
    fin <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_spinlock_bench is end entity;

architecture sim of tb_spinlock_bench is
  type nat_a is array (0 to 14) of natural;
  signal f : std_logic_vector(0 to 14);
  signal e, cy, rd, rx, ct, mc, ta : nat_a;
begin
  u_tas   : entity work.lock_harness generic map (1, 5, 0, 4, 2, 3) port map (f(0), e(0), cy(0), rd(0), rx(0), ct(0), mc(0), ta(0));
  u_ttas  : entity work.lock_harness generic map (1, 5, 1, 4, 2, 3) port map (f(1), e(1), cy(1), rd(1), rx(1), ct(1), mc(1), ta(1));
  u_tkt   : entity work.lock_harness generic map (1, 5, 2, 4, 2, 3) port map (f(2), e(2), cy(2), rd(2), rx(2), ct(2), mc(2), ta(2));
  u_tas0  : entity work.lock_harness generic map (1, 3, 0, 6, 0, 0) port map (f(3), e(3), cy(3), rd(3), rx(3), ct(3), mc(3), ta(3));
  c_tas   : entity work.lock_harness generic map (4, 6, 0, 4, 2, 3) port map (f(4), e(4), cy(4), rd(4), rx(4), ct(4), mc(4), ta(4));
  c_ttas  : entity work.lock_harness generic map (4, 6, 1, 4, 2, 3) port map (f(5), e(5), cy(5), rd(5), rx(5), ct(5), mc(5), ta(5));
  c_tkt   : entity work.lock_harness generic map (4, 6, 2, 4, 2, 3) port map (f(6), e(6), cy(6), rd(6), rx(6), ct(6), mc(6), ta(6));
  c_none  : entity work.lock_harness generic map (4, 6, 3, 4, 2, 3) port map (f(7), e(7), cy(7), rd(7), rx(7), ct(7), mc(7), ta(7));
  p2_tas  : entity work.lock_harness generic map (2, 6, 0, 4, 2, 3) port map (f(8), e(8), cy(8), rd(8), rx(8), ct(8), mc(8), ta(8));
  p2_ttas : entity work.lock_harness generic map (2, 6, 1, 4, 2, 3) port map (f(9), e(9), cy(9), rd(9), rx(9), ct(9), mc(9), ta(9));
  p8_tas  : entity work.lock_harness generic map (8, 6, 0, 4, 2, 3) port map (f(10), e(10), cy(10), rd(10), rx(10), ct(10), mc(10), ta(10));
  p8_ttas : entity work.lock_harness generic map (8, 6, 1, 4, 2, 3) port map (f(11), e(11), cy(11), rd(11), rx(11), ct(11), mc(11), ta(11));
  p8_tkt  : entity work.lock_harness generic map (8, 6, 2, 4, 2, 3) port map (f(12), e(12), cy(12), rd(12), rx(12), ct(12), mc(12), ta(12));
  h_tas2  : entity work.lock_harness generic map (2, 1, 0, 4, 0, 0) port map (f(13), e(13), cy(13), rd(13), rx(13), ct(13), mc(13), ta(13));
  h_ttas2 : entity work.lock_harness generic map (2, 1, 1, 4, 0, 0) port map (f(14), e(14), cy(14), rd(14), rx(14), ct(14), mc(14), ta(14));

  process
    variable errors : integer := 0;
    procedure expect_i(what : string; got, exp_v : integer) is
    begin
      if got /= exp_v then errors := errors + 1; report "FAIL " & what & ": got " & integer'image(got) & " expected " & integer'image(exp_v) severity note; end if;
    end procedure;
    function dec2(v, d : integer) return string is
      variable fr : integer := ((v * 100) / d) mod 100;
    begin
      if fr < 10 then return integer'image(v / d) & ".0" & integer'image(fr); else return integer'image(v / d) & "." & integer'image(fr); end if;
    end function;
  begin
    wait until f = (0 to 14 => '1');
    wait for 1 ns;
    for i in 0 to 14 loop errors := errors + e(i); end loop;
    -- hand-derived single-core totals (BUS_LAT 4, CS_LEN 2, NT 3, N 5)
    expect_i("TAS 1 core cycles",    cy(0), 3*4 + 2 + 1 + 4*(4 + 2 + 3));   expect_i("TAS 1 core BusRd",  rd(0), 1);  expect_i("TAS 1 core BusRdX",  rx(0), 2);
    expect_i("TTAS 1 core cycles",   cy(1), 4*4 + 2 + 1 + 4*(5 + 2 + 3));   expect_i("TTAS 1 core BusRd", rd(1), 2);  expect_i("TTAS 1 core BusRdX", rx(1), 2);
    expect_i("TICKET 1 core cycles", cy(2), 5*4 + 2 + 0 + 4*(5 + 2 + 3));   expect_i("TICKET 1 core BusRd", rd(2), 2); expect_i("TICKET 1 core BusRdX", rx(2), 3);
    expect_i("TAS 1 core, BUS_LAT 6, no critical-section work, no think time", cy(3), 3*6 + 0 + 1 + 2*(4 + 0 + 0));
    expect_i("TAS 2 cores cycles", cy(13), 33);   expect_i("TAS 2 cores BusRd", rd(13), 2);   expect_i("TAS 2 cores BusRdX", rx(13), 6);
    expect_i("TTAS 2 cores cycles", cy(14), 45);  expect_i("TTAS 2 cores BusRd", rd(14), 5);  expect_i("TTAS 2 cores BusRdX", rx(14), 6);
    -- the control without a lock must show what the locks prevent
    if not (mc(7) > 1) then errors := errors + 1; report "FAIL: without a lock the critical sections should overlap" severity note; end if;
    if not (ct(7) < 4 * 6) then errors := errors + 1; report "FAIL: without a lock increments should be lost" severity note; end if;
    -- traffic
    if not (rx(5) + rd(5) < rx(4) + rd(4)) then errors := errors + 1; report "FAIL: TTAS should need fewer bus transactions than TAS with 4 cores" severity note; end if;
    if not (rx(11) + rd(11) < rx(10) + rd(10)) then errors := errors + 1; report "FAIL: TTAS should need fewer bus transactions than TAS with 8 cores" severity note; end if;
    report "4 cores x 6 critical sections (24 acquisitions): bus transactions / cycles   TAS " & integer'image(rd(4) + rx(4)) & " / " & integer'image(cy(4)) & ",  TTAS " & integer'image(rd(5) + rx(5)) & " / " & integer'image(cy(5)) &
           ",  ticket " & integer'image(rd(6) + rx(6)) & " / " & integer'image(cy(6)) & "   (no lock: counter " & integer'image(ct(7)) & " of 24, up to " & integer'image(mc(7)) & " cores inside at once)" severity note;
    report "transactions per acquisition, 2 / 4 / 8 cores:  TAS " & dec2(rd(8) + rx(8), 12) & " / " & dec2(rd(4) + rx(4), 24) & " / " & dec2(rd(10) + rx(10), 48) &
           "   TTAS " & dec2(rd(9) + rx(9), 12) & " / " & dec2(rd(5) + rx(5), 24) & " / " & dec2(rd(11) + rx(11), 48) & "   (8 cores ticket: " & dec2(rd(12) + rx(12), 48) & ")" severity note;
    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED: " & integer'image(errors) & " errors" severity error; end if;
    finish;
  end process;
end architecture;
