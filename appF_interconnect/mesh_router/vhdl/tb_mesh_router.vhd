-- A reusable harness around mesh_net: per-node injectors that obey the credit protocol, per-node ejection checkers (right destination, flit order,
-- no interleaving of packets, exactly-once delivery, packet length), and a per-packet latency log.  Latency = cycle the tail flit is on the ejection
-- link minus the cycle the head flit was on the injection link.  One process owns all state and runs a scenario:
--   SCEN 0 (4x4 mesh): zero-load latencies, a hot spot (15 nodes -> node 0), 128 random packets.
--   SCEN 1 (chain):    one 40-flit packet over 4 routers; its latency exposes the credit loop.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mesh_pkg.all;

entity mesh_harness is
  generic (NX : positive := 4; NY : positive := 4; DEPTH : positive := 4; SCEN : natural := 0);
  port (done : out std_logic; errors : out integer; lat : out integer);
end entity;

architecture sim of mesh_harness is
  constant NN : positive := NX * NY;
  constant MAXF : positive := 160;
  constant MAXP : positive := 512;
  type flit_arr is array (natural range <>) of std_logic_vector(FW-1 downto 0);
  type int_arr  is array (natural range <>) of integer;

  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal inj_valid : std_logic_vector(NN-1 downto 0) := (others => '0');
  signal inj_flit : std_logic_vector(NN*FW-1 downto 0) := (others => '0');
  signal inj_credit, ej_valid : std_logic_vector(NN-1 downto 0);
  signal ej_flit : std_logic_vector(NN*FW-1 downto 0);
  signal err_overflow : std_logic;
begin
  clk <= not clk after 5 ns;
  dut : entity work.mesh_net generic map (NX, NY, DEPTH) port map (clk, rst_n, inj_valid, inj_flit, inj_credit, ej_valid, ej_flit, err_overflow);

  process (clk) begin
    if rising_edge(clk) and rst_n = '1' and err_overflow = '1' then
      report "FAIL: input FIFO overflow (credit protocol violated)" severity error;
    end if;
  end process;

  main : process
    variable fl_data : flit_arr(0 to NN*MAXF-1);
    variable fl_ready : int_arr(0 to NN*MAXF-1) := (others => 0);
    variable fl_cnt, fl_ptr, inj_cred, cur_id, nxt_seq : int_arr(0 to NN-1);
    variable p_src, p_dst, p_len, inj_cyc, ej_cyc, p_done, p_flits : int_arr(0 to MAXP-1) := (others => 0);
    variable n_pkts, delivered, cyc, errs, ej_first, ej_last, node0_first, node0_last : integer := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(1992, 32);

    impure function rnd(modulus : positive) return natural is
    begin
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
      return to_integer(seed(30 downto 16)) mod modulus;
    end function;

    function hops(s, d : natural) return natural is
      variable dx, dy : integer;
    begin
      dx := (s mod NX) - (d mod NX);  dy := (s / NX) - (d / NX);
      return abs(dx) + abs(dy);
    end function;

    procedure clear_all is
    begin
      n_pkts := 0;  delivered := 0;  ej_first := 1000000000;  ej_last := -1;  node0_first := 1000000000;  node0_last := -1;
      for nd in 0 to NN-1 loop fl_cnt(nd) := 0;  fl_ptr(nd) := 0; end loop;
      for i in 0 to MAXP-1 loop p_done(i) := 0;  p_flits(i) := 0; end loop;
    end procedure;

    procedure add_pkt(src, dst, len, t : natural) is
      variable f : std_logic_vector(FW-1 downto 0);
      variable ty : std_logic_vector(1 downto 0);
      variable id, base, k : natural;
    begin
      id := n_pkts;  n_pkts := n_pkts + 1;  p_src(id) := src;  p_dst(id) := dst;  p_len(id) := len;  base := cyc + 2 + t;
      for i in 0 to len - 1 loop
        if len = 1 then ty := T_SINGLE; elsif i = 0 then ty := T_HEAD; elsif i = len - 1 then ty := T_TAIL; else ty := T_BODY; end if;
        f := (others => '0');  f(FW-1 downto FW-2) := ty;
        f(15 downto 0) := std_logic_vector(to_unsigned(id, 16));  f(23 downto 16) := std_logic_vector(to_unsigned(i, 8));
        if i = 0 then
          f(27 downto 24) := std_logic_vector(to_unsigned(dst mod NX, 4));  f(31 downto 28) := std_logic_vector(to_unsigned(dst / NX, 4));
        end if;
        k := src * MAXF + fl_cnt(src);
        fl_data(k) := f;
        if i = 0 then fl_ready(k) := base; else fl_ready(k) := 0; end if;
        fl_cnt(src) := fl_cnt(src) + 1;
      end loop;
    end procedure;

    -- one cycle: injectors and ejection checkers, in the middle of the cycle
    procedure step is
      variable k : natural;
      variable f : std_logic_vector(FW-1 downto 0);
      variable ty : std_logic_vector(1 downto 0);
      variable id, sq : natural;
    begin
      wait until falling_edge(clk);
      for nd in 0 to NN-1 loop
        inj_valid(nd) <= '0';
        k := nd * MAXF + fl_ptr(nd);
        if fl_ptr(nd) < fl_cnt(nd) and cyc >= fl_ready(k) and inj_cred(nd) > 0 then
          f := fl_data(k);
          inj_valid(nd) <= '1';  inj_flit(nd*FW + FW-1 downto nd*FW) <= f;  inj_cred(nd) := inj_cred(nd) - 1;
          if f(FW-1 downto FW-2) = T_HEAD or f(FW-1 downto FW-2) = T_SINGLE then inj_cyc(to_integer(unsigned(f(15 downto 0)))) := cyc; end if;
          fl_ptr(nd) := fl_ptr(nd) + 1;
        end if;
        if inj_credit(nd) = '1' then inj_cred(nd) := inj_cred(nd) + 1; end if;      -- a credit pulse seen this cycle is usable from the next cycle
      end loop;
      for nd in 0 to NN-1 loop
        if ej_valid(nd) = '1' then
          f := ej_flit(nd*FW + FW-1 downto nd*FW);  ty := f(FW-1 downto FW-2);
          id := to_integer(unsigned(f(15 downto 0)));  sq := to_integer(unsigned(f(23 downto 16)));
          if cyc < ej_first then ej_first := cyc; end if;
          ej_last := cyc;
          if nd = 0 then
            if cyc < node0_first then node0_first := cyc; end if;
            node0_last := cyc;
          end if;
          if cur_id(nd) < 0 then                                              -- expecting a head
            if ty /= T_HEAD and ty /= T_SINGLE then
              errs := errs + 1;  report "FAIL node " & integer'image(nd) & ": body/tail flit without a head" severity error;
            else
              if to_integer(unsigned(f(27 downto 24))) /= (nd mod NX) or to_integer(unsigned(f(31 downto 28))) /= (nd / NX) or p_dst(id) /= nd then
                errs := errs + 1;  report "FAIL packet " & integer'image(id) & " misrouted to node " & integer'image(nd) severity error;
              end if;
              if sq /= 0 then errs := errs + 1; report "FAIL packet head index /= 0" severity error; end if;
              cur_id(nd) := id;  nxt_seq(nd) := 1;  p_flits(id) := 1;
              if ty = T_SINGLE then cur_id(nd) := -1; end if;
            end if;
          else                                                                -- inside a packet
            if id /= cur_id(nd) then
              errs := errs + 1;  report "FAIL node " & integer'image(nd) & ": flit of packet " & integer'image(id) & " interleaved into packet " & integer'image(cur_id(nd)) severity error;
            elsif ty = T_HEAD or ty = T_SINGLE then
              errs := errs + 1;  report "FAIL second head inside a packet" severity error;
            else
              if sq /= nxt_seq(nd) then errs := errs + 1; report "FAIL flit order in packet " & integer'image(id) severity error; end if;
              nxt_seq(nd) := nxt_seq(nd) + 1;  p_flits(id) := p_flits(id) + 1;
              if ty = T_TAIL then cur_id(nd) := -1; end if;
            end if;
          end if;
          if cur_id(nd) < 0 and (ty = T_TAIL or ty = T_SINGLE) then            -- packet complete
            if p_flits(id) /= p_len(id) then errs := errs + 1; report "FAIL packet " & integer'image(id) & " delivered with the wrong flit count" severity error; end if;
            if p_done(id) /= 0 then errs := errs + 1; report "FAIL packet " & integer'image(id) & " delivered twice" severity error; end if;
            p_done(id) := p_done(id) + 1;  ej_cyc(id) := cyc;  delivered := delivered + 1;
          end if;
        end if;
      end loop;
      cyc := cyc + 1;
    end procedure;

    procedure run(timeout : natural; what : string) is
      variable t : natural := 0;
    begin
      while delivered < n_pkts and t < timeout loop step; t := t + 1; end loop;
      if delivered < n_pkts then
        errs := errs + 1;
        report "FAIL " & what & ": only " & integer'image(delivered) & " of " & integer'image(n_pkts) & " packets delivered (deadlock?)" severity error;
      end if;
      for i in 1 to 10 loop step; end loop;
    end procedure;

    procedure expect_i(what : string; got, exp_v : integer) is
    begin
      if got /= exp_v then errs := errs + 1; report "FAIL " & what & ": got " & integer'image(got) & " expected " & integer'image(exp_v) severity error; end if;
    end procedure;
    impure function latency(id : natural) return integer is begin return ej_cyc(id) - inj_cyc(id); end function;
    impure function zero_load(id : natural) return integer is begin return 2 * (hops(p_src(id), p_dst(id)) + 1) + p_len(id) - 1; end function;

    variable dst, len, tt, sum_lat, sum_zl, mx : integer;
  begin
    done <= '0';  errors <= 0;  lat <= 0;
    for nd in 0 to NN-1 loop fl_cnt(nd) := 0;  fl_ptr(nd) := 0;  inj_cred(nd) := DEPTH;  cur_id(nd) := -1;  nxt_seq(nd) := 0; end loop;
    wait until falling_edge(clk);  wait until falling_edge(clk);  wait until falling_edge(clk);
    rst_n <= '1';

    if SCEN = 1 then
      clear_all;  add_pkt(0, NN - 1, 40, 0);  run(1000, "40-flit packet");
      lat <= latency(0);
    else
      -- zero-load latency: 2 (hops + 1) + flits - 1
      clear_all;  add_pkt(0, 15, 5, 0);  run(200, "corner to corner");
      expect_i("(0,0)->(3,3) hops", hops(0, 15), 6);
      expect_i("(0,0)->(3,3) 5 flits latency", latency(0), 2 * 7 + 4);
      clear_all;  add_pkt(0, 1, 1, 0);  run(200, "neighbour");   expect_i("(0,0)->(1,0) 1 flit latency", latency(0), 4);
      clear_all;  add_pkt(5, 5, 3, 0);  run(200, "self");        expect_i("(1,1)->(1,1) 3 flits latency", latency(0), 4);
      clear_all;  add_pkt(3, 8, 2, 0);  run(200, "mixed");       expect_i("(3,0)->(0,2) 2 flits latency", latency(0), 2 * 6 + 1);
      report "zero-load: corner-to-corner 5-flit packet = 18 cycles (2 x 7 routers + 4), neighbour = 4, self = 4";

      -- hot spot: all 15 other nodes send a 4-flit packet to node 0 at once
      clear_all;
      for s in 1 to 15 loop add_pkt(s, 0, 4, 0); end loop;
      run(2000, "hot spot");
      expect_i("hot spot: packets delivered", delivered, 15);
      if node0_last - node0_first < 15 * 4 - 1 then errs := errs + 1; report "FAIL hot spot: 60 flits ejected faster than one per cycle" severity error; end if;
      mx := 0;  for i in 0 to 14 loop if latency(i) > mx then mx := latency(i); end if; end loop;
      report "hot spot: 60 flits through one ejection port: first ejection t=" & integer'image(node0_first) & ", last t=" & integer'image(node0_last) &
             " (" & integer'image(node0_last - node0_first + 1) & " cycles for 60 flits), worst packet latency " & integer'image(mx);

      -- random traffic: 16 nodes x 8 packets (1..6 flits), random destinations and start times
      clear_all;
      for s in 0 to 15 loop
        for kk in 0 to 7 loop
          dst := rnd(16);  len := 1 + rnd(6);  tt := rnd(200);               -- same draw order as the SystemVerilog testbench
          add_pkt(s, dst, len, tt);
        end loop;
      end loop;
      run(20000, "random traffic");
      expect_i("random: packets delivered", delivered, 128);
      sum_lat := 0;  sum_zl := 0;
      for i in 0 to 127 loop
        if latency(i) < zero_load(i) then errs := errs + 1; report "FAIL packet " & integer'image(i) & ": latency below the zero-load bound" severity error; end if;
        sum_lat := sum_lat + latency(i);  sum_zl := sum_zl + zero_load(i);
      end loop;
      report "random: 128 packets delivered, average latency " & integer'image(sum_lat / 128) & "." & integer'image((sum_lat * 100 / 128) mod 100) &
             " cycles vs " & integer'image(sum_zl / 128) & "." & integer'image((sum_zl * 100 / 128) mod 100) & " at zero load";
    end if;
    errors <= errs;  done <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.mesh_pkg.all;

entity tb_mesh_router is end entity;

architecture sim of tb_mesh_router is
  signal clk : std_logic := '0';
  signal ru_rst : std_logic := '0';
  signal ru_in_v, ru_out_v, ru_out_cr, ru_in_cr : std_logic_vector(4 downto 0) := (others => '0');
  signal ru_in_f, ru_out_f : std_logic_vector(5*FW-1 downto 0) := (others => '0');
  signal ru_err : std_logic;
  signal d : std_logic_vector(0 to 4);
  type int5 is array (0 to 4) of integer;
  signal er, lt : int5;
begin
  clk <= not clk after 5 ns;
  -- a single router at (1,1) of a 3x3 mesh
  ru : entity work.mesh_router generic map (X => 1, Y => 1, NX => 3, NY => 3, DEPTH => 4)
    port map (clk, ru_rst, ru_in_v, ru_in_f, ru_in_cr, ru_out_v, ru_out_f, ru_out_cr, ru_err);

  m44 : entity work.mesh_harness generic map (4, 4, 4, 0) port map (d(0), er(0), lt(0));
  c2  : entity work.mesh_harness generic map (4, 1, 2, 1) port map (d(1), er(1), lt(1));
  c3  : entity work.mesh_harness generic map (4, 1, 3, 1) port map (d(2), er(2), lt(2));
  c4  : entity work.mesh_harness generic map (4, 1, 4, 1) port map (d(3), er(3), lt(3));
  c5  : entity work.mesh_harness generic map (4, 1, 5, 1) port map (d(4), er(4), lt(4));

  main : process
    variable errs : integer := 0;

    -- Routing table: dimension-order (X first), a flit for the east column goes East even when it also has to move in Y.
    procedure route_case(in_port, dx, dy, exp_port : natural) is
      variable f : std_logic_vector(FW-1 downto 0);
      variable want : std_logic_vector(4 downto 0);
    begin
      f := (others => '0');  f(FW-1 downto FW-2) := T_SINGLE;  f(15 downto 0) := x"ABCD";
      f(27 downto 24) := std_logic_vector(to_unsigned(dx, 4));  f(31 downto 28) := std_logic_vector(to_unsigned(dy, 4));
      want := (others => '0');  want(exp_port) := '1';
      wait until falling_edge(clk);  ru_rst <= '0';  wait until falling_edge(clk);  wait until falling_edge(clk);  ru_rst <= '1';
      wait until falling_edge(clk);  ru_in_v <= (others => '0');  ru_in_v(in_port) <= '1';  ru_in_f(in_port*FW + FW-1 downto in_port*FW) <= f;   -- cycle c: on the link
      wait until falling_edge(clk);  ru_in_v <= (others => '0');                                                                                  -- cycle c+1: switched
      wait until falling_edge(clk);                                                                                                               -- cycle c+2: on the output link
      if ru_out_v /= want then
        errs := errs + 1;  report "FAIL route: in " & integer'image(in_port) & " dest (" & integer'image(dx) & "," & integer'image(dy) & ") expected port " & integer'image(exp_port) severity error;
      elsif ru_out_f(exp_port*FW + FW-1 downto exp_port*FW) /= f then
        errs := errs + 1;  report "FAIL route: flit corrupted" severity error;
      end if;
    end procedure;
    procedure expect_i(what : string; got, exp_v : integer) is
    begin
      if got /= exp_v then errs := errs + 1; report "FAIL " & what & ": got " & integer'image(got) & " expected " & integer'image(exp_v) severity error; end if;
    end procedure;
  begin
    for i in 1 to 6 loop wait until falling_edge(clk); end loop;
    -- from Local:  (2,1) E  (0,1) W  (1,0) N  (1,2) S  (1,1) L  (2,0) E  (0,2) W  (2,2) E  (0,0) W
    route_case(P_L, 2, 1, P_E);  route_case(P_L, 0, 1, P_W);  route_case(P_L, 1, 0, P_N);  route_case(P_L, 1, 2, P_S);  route_case(P_L, 1, 1, P_L);
    route_case(P_L, 2, 0, P_E);  route_case(P_L, 0, 2, P_W);  route_case(P_L, 2, 2, P_E);  route_case(P_L, 0, 0, P_W);
    -- from other inputs
    route_case(P_W, 2, 1, P_E);  route_case(P_W, 1, 2, P_S);  route_case(P_W, 1, 1, P_L);  route_case(P_N, 0, 2, P_W);  route_case(P_N, 1, 2, P_S);
    report "routing: 14 destination/input combinations routed X-first (dimension order)";

    wait until d = "11111";
    wait for 1 ns;
    -- credit loop: one 40-flit packet over 4 routers; full rate needs buffering >= the 4-cycle credit round trip
    report "credit loop, 40-flit packet over 4 routers: ideal " & integer'image(2 * 4 + 39) & " cycles;  FIFO depth 2 -> " & integer'image(lt(1)) &
           ", 3 -> " & integer'image(lt(2)) & ", 4 -> " & integer'image(lt(3)) & ", 5 -> " & integer'image(lt(4));
    expect_i("D=4 sustains one flit per cycle", lt(3), 2 * 4 + 39);
    expect_i("D=5 sustains one flit per cycle", lt(4), 2 * 4 + 39);
    if not (lt(2) > lt(3)) then errs := errs + 1; report "FAIL: depth 3 should be slower than depth 4" severity error; end if;
    if not (lt(1) > lt(2)) then errs := errs + 1; report "FAIL: depth 2 should be slower than depth 3" severity error; end if;
    for i in 0 to 4 loop errs := errs + er(i); end loop;
    if ru_err = '1' then errs := errs + 1; end if;
    if errs = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errs) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
