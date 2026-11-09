-- Hand-derived expectations (see README):
--   zero load: a packet crossing K = hops + 1 routers with F flits takes 3K + F - 1 cycles from the head on the injection link to the tail on the ejection link
--              (the head needs VC allocation + switch allocation = 3 cycles per router, the body/tail flits stream right behind it).
--   credit loop: one 40-flit packet over 4 routers takes 3*4 + 39 = 51 cycles at full rate (per-VC buffer depth >= the 4-cycle credit round trip); with depth D < 4 only D flits
--                can be sent per 4 cycles, so flit i leaves at floor(i/D)*4 + (i mod D): the 40th flit is late by floor(39/D)*4 + (39 mod D) - 39  -> 51 + 38 (D=2), 51 + 13 (D=3).
--   head-of-line blocking (4x1 mesh): C = node 1 -> 3, 60 flits holds router 1's East output; A = node 0 -> 3, 20 flits, queues behind C at router 1; B = node 0 -> 1,
--              4 flits, is injected right behind A.  With ONE virtual channel B sits in A's queue until C has passed (B completes after cycle 60); with TWO virtual channels
--              B overtakes A and completes within 3*2 + 4 - 1 plus at most 4 cycles of sharing the injection port with A.
-- Ejection checkers work per (node, virtual channel): flits of one packet arrive in order, packets are never interleaved INSIDE a virtual channel, each is delivered exactly once.

-- One harness entity per scenario (one process owns all state; VHDL cannot call procedures of another entity); the top compares the numbers they report.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vc_pkg.all;

entity vc_harness is
  generic (NX : positive := 4; NY : positive := 4; NVC : positive := 2; DEPTH : positive := 4;
           SCEN : natural := 0);     -- 0 zero-load   1 credit loop   2 head-of-line blocking   3 hot spot   4 random traffic
  port (fin : out std_logic; errs : out natural; m0, m1, m2 : out natural);
end entity;

architecture sim of vc_harness is
  constant NN : positive := NX * NY;
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal inj_valid : std_logic_vector(NN-1 downto 0) := (others => '0');
  signal inj_flit : std_logic_vector(NN*FW-1 downto 0) := (others => '0');
  signal inj_credit_v, ej_valid : std_logic_vector(NN-1 downto 0);
  signal inj_credit_vc : std_logic_vector(NN*2-1 downto 0);
  signal ej_flit : std_logic_vector(NN*FW-1 downto 0);
  signal err_overflow : std_logic;
begin
  clk <= not clk after 5 ns;
  dut : entity work.vc_net
    generic map (NX => NX, NY => NY, NVC => NVC, DEPTH => DEPTH)
    port map (clk => clk, rst_n => rst_n, inj_valid => inj_valid, inj_flit => inj_flit, inj_credit_v => inj_credit_v, inj_credit_vc => inj_credit_vc,
              ej_valid => ej_valid, ej_flit => ej_flit, err_overflow => err_overflow);

  main : process
    constant MAXF : natural := 200;  constant MAXP : natural := 512;
    type int_arr is array (natural range <>) of integer;
    type flit_arr is array (natural range <>) of std_logic_vector(FW-1 downto 0);
    variable fl_data : flit_arr(0 to NN*NVC*MAXF-1);
    variable fl_ready : int_arr(0 to NN*NVC*MAXF-1);
    variable fl_cnt, fl_ptr, inj_cred, cur_id, nxt_seq : int_arr(0 to NN*NVC-1);
    variable inj_rr : int_arr(0 to NN-1);
    variable p_src, p_dst, p_len, p_vc, inj_cyc, ej_cyc, p_done, p_flits, p_ready : int_arr(0 to MAXP-1) := (others => 0);
    variable n_pkts, delivered, cyc, nerr, ej_first, ej_last, node0_first, node0_last, t_start : integer := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(1992, 32);
    variable lat_a, lat_b, sum_lat, mx, extra, expd : integer;
    variable ovf_seen : boolean := false;

    impure function rnd(n : positive) return integer is
    begin
      seed := resize(seed * to_unsigned(1664525, 32), 32) + to_unsigned(1013904223, 32);
      return to_integer(seed(30 downto 16)) mod n;
    end function;
    function hops(s, d : integer) return integer is
      variable dx, dy : integer;
    begin
      dx := (s mod NX) - (d mod NX);  dy := (s / NX) - (d / NX);
      return abs(dx) + abs(dy);
    end function;
    impure function zero_load(id : integer) return integer is begin return 3 * (hops(p_src(id), p_dst(id)) + 1) + p_len(id) - 1; end function;
    impure function latency(id : integer) return integer is begin return ej_cyc(id) - inj_cyc(id); end function;
    impure function done_at(id : integer) return integer is begin return ej_cyc(id) - t_start; end function;

    -- one cycle: injectors (one flit per node, any virtual channel with a flit and a credit, round-robin) and the ejection checkers, at the falling edge
    procedure tick is
      variable k, q, v, ty_i, id, sq, qq : integer;
      variable sent : boolean;
      variable f : std_logic_vector(FW-1 downto 0);
      variable ty : std_logic_vector(1 downto 0);
    begin
      wait until falling_edge(clk);
      if rst_n = '1' then
        for n in 0 to NN-1 loop
          inj_valid(n) <= '0';  sent := false;
          for j in 1 to NVC loop
            v := (inj_rr(n) + j) mod NVC;  q := n * NVC + v;  k := q * MAXF + fl_ptr(q);
            if (not sent) and fl_ptr(q) < fl_cnt(q) and cyc >= fl_ready(k) and inj_cred(q) > 0 then
              f := fl_data(k);
              inj_valid(n) <= '1';  inj_flit(n*FW + FW-1 downto n*FW) <= f;  inj_cred(q) := inj_cred(q) - 1;  sent := true;  inj_rr(n) := v;
              if f(FW-1 downto FW-2) = T_HEAD or f(FW-1 downto FW-2) = T_SINGLE then inj_cyc(to_integer(unsigned(f(15 downto 0)))) := cyc; end if;
              fl_ptr(q) := fl_ptr(q) + 1;
            end if;
          end loop;
          if inj_credit_v(n) = '1' then
            qq := n * NVC + to_integer(unsigned(inj_credit_vc(2*n + 1 downto 2*n)));
            inj_cred(qq) := inj_cred(qq) + 1;                             -- usable from the next cycle
          end if;
        end loop;
        for n in 0 to NN-1 loop
          if ej_valid(n) = '1' then
            f := ej_flit(n*FW + FW-1 downto n*FW);  ty := f(FW-1 downto FW-2);  id := to_integer(unsigned(f(15 downto 0)));  sq := to_integer(unsigned(f(23 downto 16)));
            v := to_integer(unsigned(f(33 downto 32)));
            if v >= NVC then
              nerr := nerr + 1;  report "FAIL node " & integer'image(n) & ": flit on nonexistent VC " & integer'image(v) severity note;
            else
              q := n * NVC + v;
              if cyc < ej_first then ej_first := cyc; end if;
              ej_last := cyc;
              if n = 0 then
                if cyc < node0_first then node0_first := cyc; end if;
                node0_last := cyc;
              end if;
              if cur_id(q) < 0 then                                                 -- expecting a head
                if ty /= T_HEAD and ty /= T_SINGLE then
                  nerr := nerr + 1;  report "FAIL node " & integer'image(n) & ": body/tail flit of packet " & integer'image(id) & " without a head" severity note;
                else
                  if to_integer(unsigned(f(27 downto 24))) /= (n mod NX) or to_integer(unsigned(f(31 downto 28))) /= (n / NX) or p_dst(id) /= n then
                    nerr := nerr + 1;  report "FAIL packet " & integer'image(id) & " misrouted to node " & integer'image(n) severity note;
                  end if;
                  if sq /= 0 then nerr := nerr + 1; report "FAIL packet " & integer'image(id) & " head has index " & integer'image(sq) severity note; end if;
                  cur_id(q) := id;  nxt_seq(q) := 1;  p_flits(id) := 1;
                  if ty = T_SINGLE then cur_id(q) := -1; end if;
                end if;
              else                                                                  -- inside a packet of this virtual channel
                if id /= cur_id(q) then
                  nerr := nerr + 1;  report "FAIL node " & integer'image(n) & ": flit of packet " & integer'image(id) & " interleaved into packet " & integer'image(cur_id(q)) & " inside one virtual channel" severity note;
                elsif ty = T_HEAD or ty = T_SINGLE then
                  nerr := nerr + 1;  report "FAIL node " & integer'image(n) & ": second head inside packet " & integer'image(id) severity note;
                else
                  if sq /= nxt_seq(q) then nerr := nerr + 1; report "FAIL packet " & integer'image(id) & " flit order: got " & integer'image(sq) & " expected " & integer'image(nxt_seq(q)) severity note; end if;
                  nxt_seq(q) := nxt_seq(q) + 1;  p_flits(id) := p_flits(id) + 1;
                  if ty = T_TAIL then cur_id(q) := -1; end if;
                end if;
              end if;
              if cur_id(q) < 0 and (ty = T_TAIL or ty = T_SINGLE) then              -- packet complete
                if p_flits(id) /= p_len(id) then nerr := nerr + 1; report "FAIL packet " & integer'image(id) & " delivered with " & integer'image(p_flits(id)) & " flits, expected " & integer'image(p_len(id)) severity note; end if;
                if p_done(id) /= 0 then nerr := nerr + 1; report "FAIL packet " & integer'image(id) & " delivered twice" severity note; end if;
                p_done(id) := p_done(id) + 1;  ej_cyc(id) := cyc;  delivered := delivered + 1;
              end if;
            end if;
          end if;
        end loop;
        if err_overflow = '1' and not ovf_seen then
          ovf_seen := true;  nerr := nerr + 1;  report "FAIL " & "[" & integer'image(NX) & "x" & integer'image(NY) & " VC=" & integer'image(NVC) & " D=" & integer'image(DEPTH) & " S=" & integer'image(SCEN) & "] " & "input FIFO overflow (credit protocol violated)" severity note;
        end if;
      end if;
      cyc := cyc + 1;
    end procedure;

    procedure clear_all is
    begin
      n_pkts := 0;  delivered := 0;  ej_first := 1000000000;  ej_last := -1;  node0_first := 1000000000;  node0_last := -1;  t_start := cyc + 2;
      for i in 0 to NN*NVC-1 loop fl_cnt(i) := 0; fl_ptr(i) := 0; end loop;
      for i in 0 to MAXP-1 loop p_done(i) := 0; p_flits(i) := 0; end loop;
    end procedure;
    procedure add_pkt(src, dst, len, t, vc : integer) is
      variable f : std_logic_vector(FW-1 downto 0);
      variable id, base, q : integer;
    begin
      id := n_pkts;  n_pkts := n_pkts + 1;  p_src(id) := src;  p_dst(id) := dst;  p_len(id) := len;  p_vc(id) := vc;  base := cyc + 2 + t;  p_ready(id) := base;
      q := src * NVC + vc;
      for i in 0 to len - 1 loop
        f := (others => '0');
        if len = 1 then f(FW-1 downto FW-2) := T_SINGLE;
        elsif i = 0 then f(FW-1 downto FW-2) := T_HEAD;
        elsif i = len - 1 then f(FW-1 downto FW-2) := T_TAIL;
        else f(FW-1 downto FW-2) := T_BODY; end if;
        f(33 downto 32) := std_logic_vector(to_unsigned(vc, 2));
        f(15 downto 0) := std_logic_vector(to_unsigned(id, 16));  f(23 downto 16) := std_logic_vector(to_unsigned(i, 8));
        if i = 0 then f(27 downto 24) := std_logic_vector(to_unsigned(dst mod NX, 4)); f(31 downto 28) := std_logic_vector(to_unsigned(dst / NX, 4)); end if;
        fl_data(q*MAXF + fl_cnt(q)) := f;
        if i = 0 then fl_ready(q*MAXF + fl_cnt(q)) := base; else fl_ready(q*MAXF + fl_cnt(q)) := 0; end if;
        fl_cnt(q) := fl_cnt(q) + 1;
      end loop;
    end procedure;
    procedure run(timeout : integer; what : string) is
      variable t : integer := 0;
    begin
      while delivered < n_pkts and t < timeout and nerr = 0 loop tick; t := t + 1; end loop;
      if delivered < n_pkts and nerr = 0 then
        nerr := nerr + 1;
        report "FAIL " & "[" & integer'image(NX) & "x" & integer'image(NY) & " VC=" & integer'image(NVC) & " D=" & integer'image(DEPTH) & " S=" & integer'image(SCEN) & "] " & what & ": only " & integer'image(delivered) & " of " & integer'image(n_pkts) & " packets delivered in " & integer'image(timeout) & " cycles (deadlock?)" severity note;
      end if;
      for i in 1 to 10 loop tick; end loop;
    end procedure;
    procedure expect_i(what : string; got, exp_v : integer) is
    begin
      if got /= exp_v then nerr := nerr + 1; report "FAIL " & "[" & integer'image(NX) & "x" & integer'image(NY) & " VC=" & integer'image(NVC) & " D=" & integer'image(DEPTH) & " S=" & integer'image(SCEN) & "] " & what & ": got " & integer'image(got) & " expected " & integer'image(exp_v) severity note; end if;
    end procedure;
  begin
    fin <= '0';  errs <= 0;  m0 <= 0;  m1 <= 0;  m2 <= 0;
    for i in 0 to NN*NVC-1 loop fl_cnt(i) := 0; fl_ptr(i) := 0; inj_cred(i) := DEPTH; cur_id(i) := -1; nxt_seq(i) := 0; end loop;
    for n in 0 to NN-1 loop inj_rr(n) := NVC - 1; end loop;
    for i in 1 to 3 loop tick; end loop;
    rst_n <= '1';
    for i in 1 to 6 loop tick; end loop;

    case SCEN is
      when 0 =>   -- zero-load latency 3K + F - 1, on either virtual channel
        clear_all;  add_pkt(0, 15, 5, 0, 0);  run(200, "corner to corner");      expect_i("(0,0)->(3,3) 5 flits", latency(0), 3 * 7 + 4);
        clear_all;  add_pkt(0, 15, 5, 0, 1);  run(200, "corner to corner vc1");  expect_i("(0,0)->(3,3) 5 flits on VC 1", latency(0), 3 * 7 + 4);
        clear_all;  add_pkt(0, 1, 1, 0, 0);   run(200, "neighbour");             expect_i("(0,0)->(1,0) 1 flit", latency(0), 6);
        clear_all;  add_pkt(5, 5, 3, 0, 1);   run(200, "self");                  expect_i("(1,1)->(1,1) 3 flits", latency(0), 5);
        clear_all;  add_pkt(3, 8, 2, 0, 0);   run(200, "mixed");                 expect_i("(3,0)->(0,2) 2 flits", latency(0), 3 * 6 + 1);
      when 1 =>   -- credit loop: one 40-flit packet over 4 routers
        clear_all;  add_pkt(0, 3, 40, 0, NVC - 1);  run(1000, "credit loop");
        if DEPTH >= 4 then expd := 51; else expd := 51 + (39 / DEPTH) * 4 + (39 mod DEPTH) - 39; end if;
        expect_i("40-flit packet, VC buffer depth " & integer'image(DEPTH), latency(0), expd);
        m0 <= latency(0);
      when 2 =>   -- head-of-line blocking: C = node 1 -> 3 (60 flits), A = node 0 -> 3 (20 flits), B = node 0 -> 1 (4 flits) behind A
        clear_all;  add_pkt(1, 3, 60, 0, 0);  add_pkt(0, 3, 20, 0, 0);  add_pkt(0, 1, 4, 0, NVC - 1);  run(2000, "head-of-line blocking");
        m0 <= done_at(2);  m1 <= done_at(1);
      when 3 =>   -- hot spot: every other node sends a 4-flit packet to node 0
        clear_all;  for s in 1 to 15 loop add_pkt(s, 0, 4, 0, s mod 2); end loop;  run(2000, "hot spot");
        expect_i("hot spot: packets delivered", delivered, 15);
        if node0_last - node0_first < 15 * 4 - 1 then nerr := nerr + 1; report "FAIL hot spot: 60 flits ejected in only " & integer'image(node0_last - node0_first + 1) & " cycles" severity note; end if;
        mx := 0;  for i in 0 to 14 loop if latency(i) > mx then mx := latency(i); end if; end loop;
        m0 <= node0_last - node0_first + 1;  m1 <= mx;
      when others =>   -- random traffic, 16 nodes x 12 packets (1..6 flits), vc = draw mod NVC
        clear_all;
        for s in 0 to 15 loop
          for kk in 0 to 11 loop
            lat_a := rnd(16);  lat_b := 1 + rnd(6);  extra := rnd(40);  expd := rnd(4);       -- dst, len, start, vc (same draw order as the SystemVerilog testbench)
            add_pkt(s, lat_a, lat_b, extra, expd mod NVC);
          end loop;
        end loop;
        run(40000, "random traffic");
        expect_i("random: packets delivered", delivered, 192);
        sum_lat := 0;
        for i in 0 to 191 loop
          if latency(i) < zero_load(i) then nerr := nerr + 1; report "FAIL packet " & integer'image(i) & ": latency below the zero-load bound" severity note; end if;
          sum_lat := sum_lat + latency(i);
        end loop;
        m0 <= sum_lat;  m1 <= ej_last - t_start;  m2 <= delivered;
    end case;
    errs <= nerr;
    fin <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.vc_pkg.all;

entity tb_vc_router is
end entity;

architecture sim of tb_vc_router is
  -- single router (1,1) of a 3x3 mesh for the routing table
  signal clk : std_logic := '0';
  signal ru_rst : std_logic := '0';
  signal ru_in_v, ru_in_cr, ru_out_v : std_logic_vector(4 downto 0) := (others => '0');
  signal ru_out_cr : std_logic_vector(4 downto 0) := (others => '0');
  signal ru_in_f, ru_out_f : std_logic_vector(5*FW-1 downto 0) := (others => '0');
  signal ru_in_crvc, ru_out_crvc : std_logic_vector(9 downto 0) := (others => '0');
  signal ru_err : std_logic;

  signal dz, dh, d2, d3, d4, d5, dh1, dh2, dr1, dr2, dr4 : std_logic;
  signal ez, eh, e2, e3, e4, e5, eh1, eh2, er1, er2, er4 : natural;
  signal zz0, zz1, zz2, hh0, hh1, hh2, c20, c21, c22, c30, c31, c32, c40, c41, c42, c50, c51, c52 : natural;
  signal a10, a11, a12, a20, a21, a22, b10, b11, b12, b20, b21, b22, b40, b41, b42 : natural;
  signal hot0, hot1, hot2 : natural;
begin
  clk <= not clk after 5 ns;
  ru : entity work.vc_router
    generic map (X => 1, Y => 1, NX => 3, NY => 3, NVC => 2, DEPTH => 4)
    port map (clk => clk, rst_n => ru_rst, in_valid => ru_in_v, in_flit => ru_in_f, in_credit_v => ru_in_cr, in_credit_vc => ru_in_crvc,
              out_valid => ru_out_v, out_flit => ru_out_f, out_credit_v => ru_out_cr, out_credit_vc => ru_out_crvc, err_overflow => ru_err);

  z   : entity work.vc_harness generic map (4, 4, 2, 4, 0) port map (dz, ez, zz0, zz1, zz2);                -- zero-load
  hs  : entity work.vc_harness generic map (4, 4, 2, 4, 3) port map (dh, eh, hot0, hot1, hot2);             -- hot spot
  c2  : entity work.vc_harness generic map (4, 1, 1, 2, 1) port map (d2, e2, c20, c21, c22);                -- credit loop, VC buffer depth 2, 3, 4 (two VCs), 5
  c3  : entity work.vc_harness generic map (4, 1, 1, 3, 1) port map (d3, e3, c30, c31, c32);
  c4  : entity work.vc_harness generic map (4, 1, 2, 4, 1) port map (d4, e4, c40, c41, c42);
  c5  : entity work.vc_harness generic map (4, 1, 1, 5, 1) port map (d5, e5, c50, c51, c52);
  hl1 : entity work.vc_harness generic map (4, 1, 1, 4, 2) port map (dh1, eh1, b10, a10, b11);              -- head-of-line blocking, one VC
  hl2 : entity work.vc_harness generic map (4, 1, 2, 4, 2) port map (dh2, eh2, b20, a20, b21);              -- ... and two VCs
  r1  : entity work.vc_harness generic map (4, 4, 1, 8, 4) port map (dr1, er1, a11, a12, a21);              -- random traffic, 8 flits of buffering per port
  r2  : entity work.vc_harness generic map (4, 4, 2, 4, 4) port map (dr2, er2, a22, b12, b22);
  r4  : entity work.vc_harness generic map (4, 4, 4, 2, 4) port map (dr4, er4, b40, b41, b42);

  main : process
    variable errors : integer := 0;
    variable f : std_logic_vector(FW-1 downto 0);
    variable exp_f : std_logic_vector(FW-1 downto 0);
    variable e2x, e3x : integer;

    procedure route_case(in_port, dx, dy, exp_port : integer) is
    begin
      f := (others => '0');  f(FW-1 downto FW-2) := T_SINGLE;  f(33 downto 32) := "01";  f(15 downto 0) := x"ABCD";
      f(27 downto 24) := std_logic_vector(to_unsigned(dx, 4));  f(31 downto 28) := std_logic_vector(to_unsigned(dy, 4));
      exp_f := f;  exp_f(33 downto 32) := "00";                             -- the router rewrites the vc field to the allocated output VC (0)
      wait until falling_edge(clk);  ru_rst <= '0';  wait until falling_edge(clk);  wait until falling_edge(clk);  ru_rst <= '1';
      wait until falling_edge(clk);  ru_in_v <= (others => '0');  ru_in_v(in_port) <= '1';  ru_in_f(in_port*FW + FW-1 downto in_port*FW) <= f;   -- on the link during cycle c
      wait until falling_edge(clk);  ru_in_v <= (others => '0');                                                                              -- c+1: virtual-channel allocation
      wait until falling_edge(clk);                                                                                                           -- c+2: switch allocation
      wait until falling_edge(clk);                                                                                                           -- c+3: on the output link
      ru_in_f <= (others => '0');
      if ru_out_v /= (4 downto 0 => '0') and ru_out_v = std_logic_vector(to_unsigned(2**exp_port, 5)) then
        if ru_out_f(exp_port*FW + FW-1 downto exp_port*FW) /= exp_f then errors := errors + 1; report "FAIL route: flit corrupted" severity note; end if;
      else
        errors := errors + 1;  report "FAIL route: in " & integer'image(in_port) & " dest (" & integer'image(dx) & "," & integer'image(dy) & "): wrong output port" severity note;
      end if;
    end procedure;
  begin
    for i in 1 to 6 loop wait until falling_edge(clk); end loop;
    -- ---- 1. routing ----
    route_case(P_L, 2, 1, P_E);  route_case(P_L, 0, 1, P_W);  route_case(P_L, 1, 0, P_N);  route_case(P_L, 1, 2, P_S);  route_case(P_L, 1, 1, P_L);
    route_case(P_L, 2, 0, P_E);  route_case(P_L, 0, 2, P_W);  route_case(P_L, 2, 2, P_E);  route_case(P_L, 0, 0, P_W);
    route_case(P_W, 2, 1, P_E);  route_case(P_W, 1, 2, P_S);  route_case(P_W, 1, 1, P_L);  route_case(P_N, 0, 2, P_W);  route_case(P_N, 1, 2, P_S);
    report "routing: 14 destination/input combinations routed X-first (dimension order), in 3 cycles" severity note;

    wait until dz = '1' and dh = '1' and d2 = '1' and d3 = '1' and d4 = '1' and d5 = '1' and dh1 = '1' and dh2 = '1' and dr1 = '1' and dr2 = '1' and dr4 = '1';
    errors := errors + ez + eh + e2 + e3 + e4 + e5 + eh1 + eh2 + er1 + er2 + er4;
    if ru_err = '1' then errors := errors + 1; end if;
    report "zero-load: corner-to-corner 5-flit packet = 25 cycles (3 x 7 routers + 4), neighbour = 6, self = 5" severity note;
    report "credit loop, 40-flit packet over 4 routers: ideal 51 cycles; VC buffer depth 2 -> " & integer'image(c20) & ", 3 -> " & integer'image(c30) & ", 4 -> " & integer'image(c40) & ", 5 -> " & integer'image(c50) severity note;
    report "head-of-line blocking: short packet B completes at cycle " & integer'image(b10) & " with 1 VC (stuck behind the blocked packet A) and at cycle " & integer'image(b20) &
           " with 2 VCs; A completes at " & integer'image(a10) & " / " & integer'image(a20) severity note;
    if not (b10 > 60) then errors := errors + 1; report "FAIL: with one VC, B should wait for the 60-flit packet C" severity note; end if;
    if not (b20 <= 3 * 2 + 4 - 1 + 4 + 2 + 3) then errors := errors + 1; report "FAIL: with two VCs, B should overtake A" severity note; end if;
    report "hot spot: 60 flits through one ejection port in " & integer'image(hot0) & " cycles (minimum 60), worst packet latency " & integer'image(hot1) severity note;
    -- random traffic with equal buffering: 1 VC x 8, 2 VC x 4, 4 VC x 2   (m0 = sum of latencies, m1 = completion time)
    report "random traffic, 192 packets, 8 flits of buffering per port: 1 VC x 8: latency sum " & integer'image(a11) & ", done at " & integer'image(a12) &
           ";  2 VC x 4: " & integer'image(a22) & ", done at " & integer'image(b12) & ";  4 VC x 2: " & integer'image(b40) & ", done at " & integer'image(b41) severity note;
    if not (a22 < a11 and b12 < a12) then errors := errors + 1; report "FAIL: 2 VCs x 4 flits should beat 1 VC x 8 flits under load" severity note; end if;
    if not (b40 < a11) then errors := errors + 1; report "FAIL: 4 VCs x 2 flits should beat 1 VC x 8 flits under load" severity note; end if;

    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED: " & integer'image(errors) & " errors" severity error; end if;
    finish;
  end process;
end architecture;
