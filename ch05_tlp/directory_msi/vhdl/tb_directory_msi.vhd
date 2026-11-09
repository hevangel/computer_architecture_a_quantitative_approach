-- Directed sequence on block 0 (P = 4, initial memory 0xA0, directory U), hand-derived.  hops(t) = message hops of the transaction; the expected latency is hops*LAT + 1 for a miss
-- and 1 for a hit; "msgs" = messages sent (request, invalidates, acknowledgements, fetch, data to home, reply).
--    # op                          directory before -> after        caches after (C0 C1 C2 C3)   hops  msgs   what happens
--    1 C0 read                     U -> S{0}                        S I I I                      2     2      request, data reply
--    2 C0 read                     S{0}                              S I I I                      hit   0
--    3 C1 read                     S{0} -> S{0,1}                    S S I I                      2     2
--    4 C2 read                     S{0,1} -> S{0,1,2}                S S S I                      2     2
--    5 C3 write 0xB1               S{0,1,2} -> M{3}                  I I I M                      4     8      request, 3 invalidates, 3 acks, reply (2k+2, k=3)
--    6 C3 write 0xB2               M{3}                              I I I M                      hit   0
--    7 C0 read  (-> 0xB2)          M{3} -> S{0,3}                    S I I S                      4     4      request, fetch, data to home (memory := 0xB2), reply
--    8 C0 write 0xC3               S{0,3} -> M{0}                    M I I I                      4     4      C0 already shares; request, 1 invalidate, 1 ack, reply (k=1)
--    9 C1 write 0xD4               M{0} -> M{1}                      I M I I                      4     4      request, fetch+invalidate, data to home (memory := 0xC3), reply
--   10 C1 read                     M{1}                              I M I I                      hit   0
--   11 C2 write 0xE5               M{1} -> M{2}                      I I M I                      4     4
--   12 C2 read blk 1               U -> S{2}                         (block 1) I I S I            2     2
--   13 C2 write blk 1 0xF6         S{2} -> M{2}                      (block 1) I I M I            2     2      the only sharer upgrades: no invalidates (k=0)
--   14 C3 write blk 2 0x17         U -> M{3}                         (block 2) I I I M            2     2
-- The random phase compares every operation with a reference model of the same protocol (states, data, message counts, latency) and checks the invariants after each operation.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dir_harness is
  generic (P : positive := 4; NB : positive := 4; LAT : positive := 2; SPARSE : boolean := false);
  port (done : out std_logic; errors : out natural; r_msgs, r_miss, r_ops : out natural);
end entity;

architecture sim of dir_harness is
  subtype word is std_logic_vector(31 downto 0);
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal req_valid, req_write : std_logic := '0';
  signal req_node : natural range 0 to P-1 := 0;
  signal req_blk : natural range 0 to NB-1 := 0;
  signal req_wdata : word := (others => '0');
  signal req_ready, resp_valid : std_logic;
  signal resp_data : word;
  signal st_req, st_rep, st_inv, st_ack, st_fetch, st_wb, st_hits, st_miss : natural;
  signal dbg_node : natural range 0 to P-1 := 0;
  signal dbg_blk : natural range 0 to NB-1 := 0;
  signal dbg_cstate, dbg_dstate : natural range 0 to 2;
  signal dbg_cdata, dbg_mem : word;
  signal dbg_dsharers : std_logic_vector(P-1 downto 0);
  -- monitor
  signal cyc : natural := 0;
  signal resp_count, resp_cyc : natural := 0;
  signal got_data : word := (others => '0');
begin
  clk <= not clk after 5 ns;
  dut : entity work.directory_msi
    generic map (P => P, NB => NB, LAT => LAT)
    port map (clk => clk, rst_n => rst_n, req_valid => req_valid, req_node => req_node, req_write => req_write, req_blk => req_blk, req_wdata => req_wdata,
              req_ready => req_ready, resp_valid => resp_valid, resp_data => resp_data,
              stat_req => st_req, stat_rep => st_rep, stat_inv => st_inv, stat_ack => st_ack, stat_fetch => st_fetch, stat_wb => st_wb, stat_hits => st_hits, stat_misses => st_miss,
              dbg_node => dbg_node, dbg_blk => dbg_blk, dbg_cstate => dbg_cstate, dbg_cdata => dbg_cdata, dbg_dstate => dbg_dstate, dbg_dsharers => dbg_dsharers, dbg_mem => dbg_mem);

  monitor : process (clk)
  begin
    if rising_edge(clk) then
      if resp_valid = '1' then resp_count <= resp_count + 1;  resp_cyc <= cyc;  got_data <= resp_data; end if;
      cyc <= cyc + 1;
    end if;
  end process;

  main : process
    type int_arr is array (natural range <>) of integer;
    type word_arr is array (natural range <>) of word;
    variable sst : int_arr(0 to P*NB-1) := (others => 0);          -- 0 I, 1 S, 2 M
    variable sdir : int_arr(0 to NB-1) := (others => 0);           -- 0 U, 1 S, 2 M
    type sh_arr is array (0 to NB-1) of std_logic_vector(P-1 downto 0);
    variable ssh : sh_arr := (others => (others => '0'));
    variable smem, gval : word_arr(0 to NB-1);
    variable sdat : word_arr(0 to P*NB-1) := (others => (others => '0'));
    variable nerr, tot_msgs, tot_miss : integer := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(5150, 32);
    variable e_hops, e_msgs, e_req, e_rep, e_inv, e_ack, e_fetch, e_wb : integer;
    variable e_hit : boolean;
    variable e_data : word;
    variable nops, node, rb, rn, rw : integer;
    variable wd : word;

    impure function rnd(n : positive) return integer is
    begin
      seed := resize(seed * to_unsigned(1664525, 32), 32) + to_unsigned(1013904223, 32);
      return to_integer(seed(30 downto 16)) mod n;
    end function;
    function w32(v : natural) return word is begin return std_logic_vector(to_unsigned(v, 32)); end function;

    -- reference model (written independently of the RTL: explicit per-node states and message bookkeeping)
    procedure ref_op(c : integer; wr : boolean; b : integer; wdv : word) is
      variable sharers, owner : integer;
    begin
      e_hit := false;  e_hops := 0;  e_req := 0;  e_rep := 0;  e_inv := 0;  e_ack := 0;  e_fetch := 0;  e_wb := 0;
      sharers := 0;  owner := -1;
      for j in 0 to P-1 loop
        if ssh(b)(j) = '1' then
          if j /= c then sharers := sharers + 1; end if;
          if sdir(b) = 2 then owner := j; end if;
        end if;
      end loop;
      if not wr then
        if sst(c*NB + b) /= 0 then e_hit := true;  e_data := sdat(c*NB + b);
        else
          e_req := 1;  e_rep := 1;  e_hops := 2;
          if sdir(b) = 2 then                                         -- owner supplies the data through the home
            e_fetch := 1;  e_wb := 1;  e_hops := 4;
            smem(b) := sdat(owner*NB + b);  sst(owner*NB + b) := 1;
          end if;
          sdat(c*NB + b) := smem(b);  e_data := smem(b);
          sst(c*NB + b) := 1;  sdir(b) := 1;  ssh(b)(c) := '1';
        end if;
      else
        if sst(c*NB + b) = 2 then e_hit := true;  sdat(c*NB + b) := wdv;
        else
          e_req := 1;  e_rep := 1;  e_hops := 2;
          if sdir(b) = 2 then
            e_fetch := 1;  e_wb := 1;  e_hops := 4;
            smem(b) := sdat(owner*NB + b);  sst(owner*NB + b) := 0;
          elsif sdir(b) = 1 and sharers > 0 then
            e_inv := sharers;  e_ack := sharers;  e_hops := 4;
            for j in 0 to P-1 loop if j /= c and ssh(b)(j) = '1' then sst(j*NB + b) := 0; end if; end loop;
          end if;
          sst(c*NB + b) := 2;  sdat(c*NB + b) := wdv;
          sdir(b) := 2;  ssh(b) := (others => '0');  ssh(b)(c) := '1';
        end if;
        e_data := wdv;
      end if;
      if wr then gval(b) := wdv; end if;
      e_msgs := e_req + e_rep + e_inv + e_ack + e_fetch + e_wb;
    end procedure;

    procedure check_state(b : integer; what : string) is
      variable owners, nshare : integer;
    begin
      dbg_blk <= b;
      for j in 0 to P-1 loop
        dbg_node <= j;  wait for 1 ns;
        if dbg_cstate /= sst(j*NB + b) then nerr := nerr + 1; report "FAIL [" & what & "] node " & integer'image(j) & " block " & integer'image(b) & " state " & integer'image(dbg_cstate) & " expected " & integer'image(sst(j*NB + b)) severity note; end if;
        if sst(j*NB + b) /= 0 and dbg_cdata /= sdat(j*NB + b) then nerr := nerr + 1; report "FAIL [" & what & "] node " & integer'image(j) & " block " & integer'image(b) & " data wrong" severity note; end if;
      end loop;
      wait for 1 ns;
      if dbg_dstate /= sdir(b) or dbg_dsharers /= ssh(b) then nerr := nerr + 1; report "FAIL [" & what & "] directory block " & integer'image(b) & " differs from the reference" severity note; end if;
      if sdir(b) /= 2 and dbg_mem /= smem(b) then nerr := nerr + 1; report "FAIL [" & what & "] block " & integer'image(b) & " memory wrong" severity note; end if;
      owners := 0;  nshare := 0;
      for j in 0 to P-1 loop
        if sst(j*NB + b) = 2 then owners := owners + 1; end if;
        if sst(j*NB + b) = 1 then nshare := nshare + 1; end if;
        if (sst(j*NB + b) /= 0) /= (ssh(b)(j) = '1') then nerr := nerr + 1; report "FAIL [" & what & "] sharer bit " & integer'image(j) & " of block " & integer'image(b) & " disagrees with the cache" severity note; end if;
      end loop;
      if owners > 1 or (owners = 1 and nshare > 0) then nerr := nerr + 1; report "FAIL [" & what & "] invariant: block " & integer'image(b) & " has " & integer'image(owners) & " owners and " & integer'image(nshare) & " sharers" severity note; end if;
      if sdir(b) = 0 and owners + nshare /= 0 then nerr := nerr + 1; report "FAIL [" & what & "] invariant: uncached block is cached" severity note; end if;
    end procedure;

    -- drive one operation, wait for its response, compare everything
    procedure do_op(c : integer; wr : boolean; b : integer; wdv : word; exp_hops, exp_msgs : integer; what : string) is
      variable t0, exp_lat, rc0, m_before, m_after, d_req, d_rep, d_inv, d_ack, d_fetch, d_wb : integer;
    begin
      while req_ready /= '1' loop wait until falling_edge(clk); end loop;
      wait until falling_edge(clk);
      m_before := st_req + st_rep + st_inv + st_ack + st_fetch + st_wb;
      d_req := st_req;  d_rep := st_rep;  d_inv := st_inv;  d_ack := st_ack;  d_fetch := st_fetch;  d_wb := st_wb;
      ref_op(c, wr, b, wdv);
      rc0 := resp_count;
      req_valid <= '1';  req_node <= c;  req_blk <= b;  req_wdata <= wdv;  if wr then req_write <= '1'; else req_write <= '0'; end if;
      t0 := cyc;
      wait until falling_edge(clk);  req_valid <= '0';
      while resp_count = rc0 loop wait until falling_edge(clk); end loop;
      if e_hit then exp_lat := 1; else exp_lat := e_hops * LAT + 1; end if;
      if resp_cyc - t0 /= exp_lat then nerr := nerr + 1; report "FAIL [" & what & "] latency " & integer'image(resp_cyc - t0) & " expected " & integer'image(exp_lat) severity note; end if;
      if exp_hops >= 0 then
        if (e_hit and exp_hops /= 0) or ((not e_hit) and exp_hops /= e_hops) then nerr := nerr + 1; report "FAIL [" & what & "] reference model has " & integer'image(e_hops) & " hops, hand-derived " & integer'image(exp_hops) severity note; end if;
      end if;
      if exp_msgs >= 0 and e_msgs /= exp_msgs then nerr := nerr + 1; report "FAIL [" & what & "] reference model sends " & integer'image(e_msgs) & " messages, hand-derived " & integer'image(exp_msgs) severity note; end if;
      wait until falling_edge(clk);  wait until falling_edge(clk);
      m_after := st_req + st_rep + st_inv + st_ack + st_fetch + st_wb;
      if m_after - m_before /= e_msgs then nerr := nerr + 1; report "FAIL [" & what & "] " & integer'image(m_after - m_before) & " messages sent, expected " & integer'image(e_msgs) severity note; end if;
      if st_req - d_req /= e_req or st_rep - d_rep /= e_rep or st_inv - d_inv /= e_inv or st_ack - d_ack /= e_ack or st_fetch - d_fetch /= e_fetch or st_wb - d_wb /= e_wb then
        nerr := nerr + 1; report "FAIL [" & what & "] message types differ" severity note;
      end if;
      if (not wr) and got_data /= gval(b) then nerr := nerr + 1; report "FAIL [" & what & "] read returned the wrong value" severity note; end if;
      tot_msgs := tot_msgs + e_msgs;  if not e_hit then tot_miss := tot_miss + 1; end if;
      check_state(b, what);
    end procedure;
  begin
    done <= '0';  errors <= 0;  r_msgs <= 0;  r_miss <= 0;  r_ops <= 0;
    for i in 0 to NB-1 loop smem(i) := w32(16#A0# + i);  gval(i) := w32(16#A0# + i); end loop;
    wait until falling_edge(clk);  wait until falling_edge(clk);  rst_n <= '1';
    wait until falling_edge(clk);  wait until falling_edge(clk);

    if P = 4 and NB >= 3 then
      --        node wr blk data      hops msgs  what
      do_op(0, false, 0, w32(0),      2, 2, "1: C0 read, dir U");
      do_op(0, false, 0, w32(0),      0, 0, "2: C0 read hit");
      do_op(1, false, 0, w32(0),      2, 2, "3: C1 read, dir S");
      do_op(2, false, 0, w32(0),      2, 2, "4: C2 read, dir S");
      do_op(3, true,  0, w32(16#B1#), 4, 8, "5: C3 write, 3 sharers: request + 3 inv + 3 ack + reply");
      do_op(3, true,  0, w32(16#B2#), 0, 0, "6: C3 write hit in M");
      do_op(0, false, 0, w32(0),      4, 4, "7: C0 read, dir M: fetch from C3");
      do_op(0, true,  0, w32(16#C3#), 4, 4, "8: C0 write while sharing with C3: 1 inv + 1 ack");
      do_op(1, true,  0, w32(16#D4#), 4, 4, "9: C1 write, dir M: fetch+invalidate C0");
      do_op(1, false, 0, w32(0),      0, 0, "10: C1 read hit in M");
      do_op(2, true,  0, w32(16#E5#), 4, 4, "11: C2 write, dir M");
      do_op(2, false, 1, w32(0),      2, 2, "12: C2 read block 1");
      do_op(2, true,  1, w32(16#F6#), 2, 2, "13: C2 write block 1: sole sharer upgrades, no invalidates");
      do_op(3, true,  2, w32(16#17#), 2, 2, "14: C3 write block 2, dir U");
    end if;

    -- random phase (sequential consistency per block)
    tot_msgs := 0;  tot_miss := 0;
    if P = 4 then nops := 3000; else nops := 4000; end if;
    for i in 0 to nops - 1 loop
      rb := rnd(NB);  rn := rnd(P);  rw := rnd(100);  wd := std_logic_vector(seed xor x"5A5A5A5A");
      if SPARSE then node := (rb * 3 + (rn mod 3)) mod P; else node := rn; end if;
      do_op(node, rw < 35, rb, wd, -1, -1, "random " & integer'image(i));
    end loop;
    r_msgs <= tot_msgs;  r_miss <= tot_miss;  r_ops <= nops;
    errors <= nerr;  done <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_directory_msi is end entity;

architecture sim of tb_directory_msi is
  signal d0, d1, d2, d3 : std_logic;
  signal e0, e1, e2, e3, m0, m1, m2, m3, x0, x1, x2, x3, o0, o1, o2, o3 : natural;
begin
  h2  : entity work.dir_harness generic map (4, 4, 2, false)  port map (d0, e0, m0, x0, o0);
  h3  : entity work.dir_harness generic map (4, 4, 3, false)  port map (d1, e1, m1, x1, o1);
  s4  : entity work.dir_harness generic map (4, 8, 2, true)   port map (d2, e2, m2, x2, o2);
  s16 : entity work.dir_harness generic map (16, 8, 2, true)  port map (d3, e3, m3, x3, o3);

  process
    variable errors : integer;
  begin
    wait until d0 = '1' and d1 = '1' and d2 = '1' and d3 = '1';
    errors := e0 + e1 + e2 + e3;
    report "random sharing, 4 nodes (every node touches every block): " & integer'image(x0) & " misses in " & integer'image(o0) & " operations, " & integer'image(m0) &
           " messages = " & integer'image(m0 / x0) & "." & integer'image(((m0 * 100 / x0) mod 100) / 10) & integer'image((m0 * 100 / x0) mod 10) & " per miss; a snooping bus would broadcast to 3 caches per miss" severity note;
    report "sparse sharing, 16 nodes (each block shared by 3 nodes): " & integer'image(x3) & " misses, " & integer'image(m3) & " messages = " & integer'image(m3 / x3) & "." &
           integer'image(((m3 * 100 / x3) mod 100) / 10) & integer'image((m3 * 100 / x3) mod 10) & " per miss, where a broadcast would reach 15 caches per miss" severity note;
    if not (m3 * 3 < x3 * 15) then errors := errors + 1; report "FAIL: directory traffic is not below a third of the broadcast traffic at 16 nodes" severity note; end if;
    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED: " & integer'image(errors) & " errors" severity error; end if;
    finish;
  end process;
end architecture;
