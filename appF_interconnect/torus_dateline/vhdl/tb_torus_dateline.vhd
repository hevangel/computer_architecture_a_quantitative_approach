-- Torus 4x4 (ring distance = the shorter way round, ties go East / South), NVC = 2: class 0 = VC 0, class 1 = VC 1.
-- Hand-derived expectations (see README):
--   routing and VC classes of single routers (router_rig): the output port is the shorter way round each ring, X before Y, a tie goes East / South;
--        the output VC is class 1 exactly when the hop crosses the dateline link (East from x = 3, West from x = 0, South from y = 3, North from y = 0) or when the packet
--        is already in class 1 and stays in the same ring; entering a new dimension (from the Local port or after a turn) restarts at class 0; ejection takes any VC (lowest free).
--   zero load: 3K + F - 1 with K = ring distance in X + ring distance in Y + 1 routers: (0,0)->(3,0) 5 flits = 3*2+4 = 10 (the mesh route would need 4 routers = 16),
--        (0,0)->(3,3) = 3*3+4 = 13 (mesh: 25), (1,1)->(3,3) = 3*5+4 = 19.
--   deadlock: on a ring of 4 every node sends a 20-flit packet two hops East.  With ONE virtual channel and no dateline every packet holds its first link and waits for the next one,
--        which is held by the next packet: the packets never arrive.  With the dateline classes (2 VCs) the same traffic is delivered.  The same holds for the 4x4 torus under the
--        "shift by (2,2)" pattern with 16-flit packets.
-- Ejection checkers work per (node, virtual channel); injection obeys per-VC credits.
-- One harness entity per scenario (one process owns all state; VHDL cannot call procedures of another entity); the top compares the numbers they report.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vc_pkg.all;

entity torus_harness is
  generic (NX : positive := 4; NY : positive := 4; NVC : positive := 2; DEPTH : positive := 4; DATELINE : boolean := true;
           SCEN : natural := 0);     -- 0 zero-load   1 ring (every node sends 2 hops East)   2 shift by (2,2)   3 random traffic
  port (fin : out std_logic; errs : out natural; m0, m1, m2, m3, m4 : out natural);
end entity;

architecture sim of torus_harness is
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
  dut : entity work.torus_net
    generic map (NX => NX, NY => NY, NVC => NVC, DEPTH => DEPTH, DATELINE => DATELINE)
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
    variable lat_a, lat_b, sum_lat, mx, extra, expd, hop_t, hop_m : integer;
    variable ovf_seen : boolean := false;

    impure function rnd(n : positive) return integer is
    begin
      seed := resize(seed * to_unsigned(1664525, 32), 32) + to_unsigned(1013904223, 32);
      return to_integer(seed(30 downto 16)) mod n;
    end function;
    function ring(a, b, n : integer) return integer is      -- distance along the shorter way round a ring of n nodes
      variable d : integer;
    begin
      d := ((a - b) mod n + n) mod n;
      if d < n - d then return d; else return n - d; end if;
    end function;
    function hops(s, d : integer) return integer is begin return ring(s mod NX, d mod NX, NX) + ring(s / NX, d / NX, NY); end function;
    function mesh_hops(s, d : integer) return integer is
    begin
      return abs((s mod NX) - (d mod NX)) + abs((s / NX) - (d / NX));
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
    -- run without treating a timeout as an error (used to demonstrate a deadlock)
    procedure run_quiet(timeout : integer) is
      variable t : integer := 0;
    begin
      while delivered < n_pkts and t < timeout and nerr = 0 loop tick; t := t + 1; end loop;
    end procedure;
    procedure expect_i(what : string; got, exp_v : integer) is
    begin
      if got /= exp_v then nerr := nerr + 1; report "FAIL " & "[" & integer'image(NX) & "x" & integer'image(NY) & " VC=" & integer'image(NVC) & " D=" & integer'image(DEPTH) & " S=" & integer'image(SCEN) & "] " & what & ": got " & integer'image(got) & " expected " & integer'image(exp_v) severity note; end if;
    end procedure;
  begin
    fin <= '0';  errs <= 0;  m0 <= 0;  m1 <= 0;  m2 <= 0;  m3 <= 0;  m4 <= 0;
    for i in 0 to NN*NVC-1 loop fl_cnt(i) := 0; fl_ptr(i) := 0; inj_cred(i) := DEPTH; cur_id(i) := -1; nxt_seq(i) := 0; end loop;
    for n in 0 to NN-1 loop inj_rr(n) := NVC - 1; end loop;
    for i in 1 to 3 loop tick; end loop;
    rst_n <= '1';
    for i in 1 to 6 loop tick; end loop;

    case SCEN is
      when 0 =>   -- zero-load latency 3K + F - 1 with ring distances
        clear_all;  add_pkt(0, 3, 5, 0, 0);    run(200, "wrap East");   expect_i("(0,0)->(3,0) 5 flits", latency(0), 3 * 2 + 4);
        clear_all;  add_pkt(0, 2, 5, 0, 0);    run(200, "tie");         expect_i("(0,0)->(2,0) 5 flits", latency(0), 3 * 3 + 4);
        clear_all;  add_pkt(0, 15, 5, 0, 1);   run(200, "corner");      expect_i("(0,0)->(3,3) 5 flits", latency(0), 3 * 3 + 4);
        clear_all;  add_pkt(5, 15, 5, 0, 0);   run(200, "diagonal");    expect_i("(1,1)->(3,3) 5 flits", latency(0), 3 * 5 + 4);
        clear_all;  add_pkt(12, 0, 5, 0, 0);   run(200, "wrap South");  expect_i("(0,3)->(0,0) 5 flits", latency(0), 3 * 2 + 4);
        clear_all;  add_pkt(5, 5, 3, 0, 0);    run(200, "self");        expect_i("(1,1)->(1,1) 3 flits", latency(0), 5);
      when 1 =>   -- ring of 4: every node sends a 20-flit packet two hops East
        clear_all;  for s in 0 to 3 loop add_pkt(s, (s + 2) mod 4, 20, 0, 0); end loop;
        if DATELINE then
          run(3000, "ring with dateline");  expect_i("ring with dateline classes: packets delivered", delivered, 4);
        else
          run_quiet(3000);
          if delivered >= 4 then nerr := nerr + 1; report "FAIL: the ring without virtual-channel classes should deadlock but delivered " & integer'image(delivered) & " packets" severity note; end if;
        end if;
        m0 <= delivered;  if ej_last >= t_start then m1 <= ej_last - t_start; else m1 <= 0; end if;
      when 2 =>   -- 4x4 torus, shift by (2,2), 16-flit packets
        clear_all;  for s in 0 to 15 loop add_pkt(s, ((s mod 4 + 2) mod 4) + 4 * ((s / 4 + 2) mod 4), 16, 0, 0); end loop;
        if DATELINE then
          run(5000, "shift with dateline");  expect_i("shift (2,2) with dateline classes: packets delivered", delivered, 16);
        else
          run_quiet(5000);
          if delivered >= 16 then nerr := nerr + 1; report "FAIL: the torus with one VC and no dateline should deadlock under shift (2,2) but delivered " & integer'image(delivered) & " packets" severity note; end if;
        end if;
        m0 <= delivered;  if ej_last >= t_start then m1 <= ej_last - t_start; else m1 <= 0; end if;
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
        sum_lat := 0;  mx := 0;  hop_t := 0;  hop_m := 0;
        for i in 0 to 191 loop
          if latency(i) < zero_load(i) then nerr := nerr + 1; report "FAIL packet " & integer'image(i) & ": latency below the zero-load bound" severity note; end if;
          sum_lat := sum_lat + latency(i);  mx := mx + zero_load(i);
          hop_t := hop_t + hops(p_src(i), p_dst(i));  hop_m := hop_m + mesh_hops(p_src(i), p_dst(i));
        end loop;
        m0 <= sum_lat;  m1 <= ej_last - t_start;  m2 <= hop_t;  m3 <= hop_m;  m4 <= mx;
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

entity tb_torus_dateline is
end entity;

architecture sim of tb_torus_dateline is
  -- five single routers of the 4x4 torus, to check routing and the output virtual channel
  type nat5 is array (0 to 4) of natural;
  constant RX : nat5 := (0, 3, 1, 2, 0);
  constant RY : nat5 := (0, 0, 0, 0, 3);
  type vec5 is array (0 to 4) of std_logic_vector(4 downto 0);
  type flits5 is array (0 to 4) of std_logic_vector(5*FW-1 downto 0);
  type cvc5 is array (0 to 4) of std_logic_vector(9 downto 0);
  signal clk : std_logic := '0';
  signal ru_rst : std_logic_vector(0 to 4) := (others => '0');
  signal ru_in_v, ru_in_cr, ru_out_v, ru_out_cr : vec5 := (others => (others => '0'));
  signal ru_in_f, ru_out_f : flits5 := (others => (others => '0'));
  signal ru_in_crvc, ru_out_crvc : cvc5 := (others => (others => '0'));
  signal ru_err : std_logic_vector(0 to 4);

  signal dz, dr2, dr1, ds2, ds1, dn2, dn4 : std_logic;
  signal ez, er2, er1, es2, es1, en2, en4 : natural;
  signal z0, z1, z2, z3, z4, r20, r21, r22, r23, r24, r10, r11, r12, r13, r14, s20, s21, s22, s23, s24, s10, s11, s12, s13, s14 : natural;
  signal n20, n21, n22, n23, n24, n40, n41, n42, n43, n44 : natural;
begin
  clk <= not clk after 5 ns;
  rigs : for r in 0 to 4 generate
    ru : entity work.torus_router
      generic map (X => RX(r), Y => RY(r), NX => 4, NY => 4, NVC => 2, DEPTH => 4, DATELINE => true)
      port map (clk => clk, rst_n => ru_rst(r), in_valid => ru_in_v(r), in_flit => ru_in_f(r), in_credit_v => ru_in_cr(r), in_credit_vc => ru_in_crvc(r),
                out_valid => ru_out_v(r), out_flit => ru_out_f(r), out_credit_v => ru_out_cr(r), out_credit_vc => ru_out_crvc(r), err_overflow => ru_err(r));
  end generate;

  z    : entity work.torus_harness generic map (4, 4, 2, 4, true, 0)  port map (dz, ez, z0, z1, z2, z3, z4);              -- zero load
  ring2: entity work.torus_harness generic map (4, 1, 2, 4, true, 1)  port map (dr2, er2, r20, r21, r22, r23, r24);      -- ring, dateline classes
  ring1: entity work.torus_harness generic map (4, 1, 1, 4, false, 1) port map (dr1, er1, r10, r11, r12, r13, r14);      -- ring, one VC (deadlocks)
  sh2  : entity work.torus_harness generic map (4, 4, 2, 4, true, 2)  port map (ds2, es2, s20, s21, s22, s23, s24);      -- shift by (2,2), dateline classes
  sh1  : entity work.torus_harness generic map (4, 4, 1, 4, false, 2) port map (ds1, es1, s10, s11, s12, s13, s14);      -- shift by (2,2), one VC (deadlocks)
  rn2  : entity work.torus_harness generic map (4, 4, 2, 4, true, 3)  port map (dn2, en2, n20, n21, n22, n23, n24);      -- random traffic
  rn4  : entity work.torus_harness generic map (4, 4, 4, 2, true, 3)  port map (dn4, en4, n40, n41, n42, n43, n44);      -- random traffic, 2 VCs per class

  main : process
    variable errors : integer := 0;
    variable f, exp_f : std_logic_vector(FW-1 downto 0);

    procedure probe(r, in_port, in_vc, dx, dy, exp_port, exp_vc : integer) is
    begin
      f := (others => '0');  f(FW-1 downto FW-2) := T_SINGLE;  f(33 downto 32) := std_logic_vector(to_unsigned(in_vc, 2));  f(15 downto 0) := x"ABCD";
      f(27 downto 24) := std_logic_vector(to_unsigned(dx, 4));  f(31 downto 28) := std_logic_vector(to_unsigned(dy, 4));
      exp_f := f;  exp_f(33 downto 32) := std_logic_vector(to_unsigned(exp_vc, 2));
      wait until falling_edge(clk);  ru_rst(r) <= '0';  wait until falling_edge(clk);  wait until falling_edge(clk);  ru_rst(r) <= '1';
      wait until falling_edge(clk);  ru_in_v(r) <= (others => '0');  ru_in_v(r)(in_port) <= '1';  ru_in_f(r)(in_port*FW + FW-1 downto in_port*FW) <= f;   -- on the link during cycle c
      wait until falling_edge(clk);  ru_in_v(r) <= (others => '0');                                                                                         -- c+1: VC allocation
      wait until falling_edge(clk);                                                                                                                         -- c+2: switch allocation
      wait until falling_edge(clk);                                                                                                                         -- c+3: on the output link
      ru_in_f(r) <= (others => '0');
      if ru_out_v(r) = std_logic_vector(to_unsigned(2**exp_port, 5)) then
        if ru_out_f(r)(exp_port*FW + FW-1 downto exp_port*FW) /= exp_f then
          errors := errors + 1;
          report "FAIL router (" & integer'image(RX(r)) & "," & integer'image(RY(r)) & "): in " & integer'image(in_port) & " vc " & integer'image(in_vc) & " dest (" & integer'image(dx) & "," & integer'image(dy) & "): wrong output vc (expected " & integer'image(exp_vc) & ")" severity note;
        end if;
      else
        errors := errors + 1;
        report "FAIL router (" & integer'image(RX(r)) & "," & integer'image(RY(r)) & "): in " & integer'image(in_port) & " vc " & integer'image(in_vc) & " dest (" & integer'image(dx) & "," & integer'image(dy) & "): wrong output port (expected " & integer'image(exp_port) & ")" severity note;
      end if;
    end procedure;
  begin
    for i in 1 to 6 loop wait until falling_edge(clk); end loop;
    -- ---- 1. routing and dateline classes of single routers (0: (0,0)  1: (3,0)  2: (1,0)  3: (2,0)  4: (0,3)) ----
    probe(0, P_L, 0, 1, 0, P_E, 0);  probe(0, P_L, 0, 2, 0, P_E, 0);  probe(0, P_L, 0, 3, 0, P_W, 1);
    probe(0, P_L, 0, 0, 1, P_S, 0);  probe(0, P_L, 0, 0, 2, P_S, 0);  probe(0, P_L, 0, 0, 3, P_N, 1);
    probe(0, P_L, 0, 3, 3, P_W, 1);  probe(0, P_L, 0, 2, 3, P_E, 0);  probe(0, P_L, 0, 0, 0, P_L, 0);
    probe(1, P_L, 0, 0, 0, P_E, 1);  probe(1, P_W, 0, 0, 0, P_E, 1);  probe(1, P_W, 1, 1, 0, P_E, 1);
    probe(1, P_W, 0, 3, 2, P_S, 0);  probe(1, P_W, 1, 3, 2, P_S, 0);
    probe(2, P_W, 1, 3, 0, P_E, 1);  probe(2, P_W, 0, 3, 0, P_E, 0);  probe(2, P_W, 1, 1, 0, P_L, 0);
    probe(3, P_L, 0, 3, 0, P_E, 0);  probe(3, P_W, 1, 0, 0, P_E, 1);
    probe(4, P_L, 0, 0, 0, P_S, 1);  probe(4, P_N, 0, 0, 1, P_S, 1);
    if errors /= 0 then
      report "TEST FAILED: " & integer'image(errors) & " errors in the routing/dateline-class checks" severity error;
    end if;
    report "routing: 22 router/input/destination combinations checked (shorter way round each ring, X first, dateline class on the output VC)" severity note;

    wait until dz = '1' and dr2 = '1' and dr1 = '1' and ds2 = '1' and ds1 = '1' and dn2 = '1' and dn4 = '1';
    errors := errors + ez + er2 + er1 + es2 + es1 + en2 + en4;
    for r in 0 to 4 loop if ru_err(r) = '1' then errors := errors + 1; end if; end loop;
    report "zero-load: (0,0)->(3,0) = 10 cycles (mesh would take 16), (0,0)->(3,3) = 13 (mesh 25), (1,1)->(3,3) = 19" severity note;
    report "ring of 4, every node sends 20 flits two hops East: 1 VC delivers " & integer'image(r10) & " of 4 packets in 3000 cycles (DEADLOCK); 2 VCs with the dateline deliver all " & integer'image(r20) & " by cycle " & integer'image(r21) severity note;
    report "4x4 torus, shift by (2,2), 16-flit packets: 1 VC delivers " & integer'image(s10) & " of 16 (DEADLOCK); 2 VCs with the dateline deliver all " & integer'image(s20) & " by cycle " & integer'image(s21) severity note;
    if not (n22 < n23) then errors := errors + 1; report "FAIL: the torus routes should be shorter than the mesh routes" severity note; end if;
    report "random traffic, 192 packets: " & integer'image(n22) & " hops in total on the torus against " & integer'image(n23) & " on a mesh;  latency sum " & integer'image(n20) & " (2 VC x 4, zero-load sum " & integer'image(n24) &
           "), " & integer'image(n40) & " (4 VC x 2); all delivered by cycle " & integer'image(n21) & " / " & integer'image(n41) severity note;
    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED: " & integer'image(errors) & " errors" severity error; end if;
    finish;
  end process;
end architecture;
