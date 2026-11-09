-- Directory-based MSI cache coherence (Chapter 5: distributed shared memory, directory protocols).
--
-- P nodes, each with a private cache holding one line per block, NB blocks, ONE HOME DIRECTORY (with the memory) that keeps, per block, a state and a SHARER BIT VECTOR:
--   directory state   U  uncached (memory has the only copy)     S  shared by the nodes whose bit is set (memory is up to date)     M  modified: ONE sharer bit = the owner
--   cache state       I invalid    S shared (read-only, clean)    M modified (read/write, dirty)
-- Unlike the snooping bus of mesi_snoopy there is no broadcast: every transaction is a few POINT-TO-POINT MESSAGES between the requester, the home and the nodes named by the directory.
-- A node sends its request to the home; the home serialises requests (one transaction at a time) and, depending on the directory state, replies directly or involves the other nodes:
--   read miss,  dir U or S : request, data reply                                                   2 messages, 2 hops
--   read miss,  dir M      : request, FETCH to the owner (owner -> S), data to the home (memory is updated), data reply     4 messages, 4 hops
--   write miss, dir U      : request, data reply                                                   2 messages, 2 hops
--   write, dir S, nobody else shares (incl. the requester upgrading its own S copy)              2 messages, 2 hops
--   write, dir S, k other sharers : request, k INVALIDATES (parallel), k acknowledgements, reply   2k + 2 messages, 4 hops
--   write miss, dir M      : request, FETCH+INVALIDATE to the owner, data to the home, reply       4 messages, 4 hops
-- Timing: every message takes LAT cycles; a node or the home acts in the cycle a message arrives.  A request accepted in cycle t therefore completes (resp_valid) in cycle t + hops*LAT + 1;
-- a hit answers in cycle t + 1.  The model applies the state changes when the transaction completes (the home serialises, so nobody can observe the intermediate states).
-- Statistics count messages by type.  Caches are large enough to hold every block (no replacements; see the exercises).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity directory_msi is
  generic (P : positive := 4; NB : positive := 4; LAT : positive := 2; DW : positive := 32);
  port (
    clk, rst_n   : in  std_logic;
    req_valid    : in  std_logic;
    req_node     : in  natural range 0 to P-1;
    req_write    : in  std_logic;
    req_blk      : in  natural range 0 to NB-1;
    req_wdata    : in  std_logic_vector(DW-1 downto 0);
    req_ready    : out std_logic;
    resp_valid   : out std_logic;
    resp_data    : out std_logic_vector(DW-1 downto 0);
    stat_req, stat_rep, stat_inv, stat_ack, stat_fetch, stat_wb, stat_hits, stat_misses : out natural;
    dbg_node     : in  natural range 0 to P-1;
    dbg_blk      : in  natural range 0 to NB-1;
    dbg_cstate   : out natural range 0 to 2;
    dbg_cdata    : out std_logic_vector(DW-1 downto 0);
    dbg_dstate   : out natural range 0 to 2;
    dbg_dsharers : out std_logic_vector(P-1 downto 0);
    dbg_mem      : out std_logic_vector(DW-1 downto 0)
  );
end entity;

architecture rtl of directory_msi is
  constant C_I : natural := 0;  constant C_S : natural := 1;  constant C_M : natural := 2;
  constant D_U : natural := 0;  constant D_S : natural := 1;  constant D_M : natural := 2;
  type data_t is array (natural range <>) of std_logic_vector(DW-1 downto 0);
  type nat_t  is array (natural range <>) of natural;
  type sh_t   is array (natural range <>) of std_logic_vector(P-1 downto 0);

  function init_mem return data_t is
    variable r : data_t(0 to NB-1);
  begin
    for i in 0 to NB-1 loop r(i) := std_logic_vector(to_unsigned(16#A0# + i, DW)); end loop;
    return r;
  end function;

  signal cst  : nat_t(0 to P*NB-1) := (others => C_I);
  signal cdat : data_t(0 to P*NB-1) := (others => (others => '0'));
  signal dst  : nat_t(0 to NB-1) := (others => D_U);
  signal dsh  : sh_t(0 to NB-1) := (others => (others => '0'));
  signal mem  : data_t(0 to NB-1) := init_mem;
  signal busy : std_logic := '0';
  signal cnt  : natural := 0;
  signal r_node : natural range 0 to P-1 := 0;
  signal r_wr : std_logic := '0';
  signal r_blk : natural range 0 to NB-1 := 0;
  signal r_wdata : std_logic_vector(DW-1 downto 0) := (others => '0');
  signal s_req, s_rep, s_inv, s_ack, s_fetch, s_wb, s_hits, s_miss : natural := 0;
  signal rv : std_logic := '0';
  signal rd : std_logic_vector(DW-1 downto 0) := (others => '0');

  -- decode of the current request: the incoming one while idle, the latched one while a transaction is in flight
  signal c, b, k, owner, hops : natural := 0;
  signal wr, hit : boolean := false;
  signal cs, ds : natural := 0;
  signal sh, oth : std_logic_vector(P-1 downto 0) := (others => '0');
  signal wd : std_logic_vector(DW-1 downto 0) := (others => '0');
begin
  req_ready <= not busy;
  resp_valid <= rv;  resp_data <= rd;
  stat_req <= s_req;  stat_rep <= s_rep;  stat_inv <= s_inv;  stat_ack <= s_ack;  stat_fetch <= s_fetch;  stat_wb <= s_wb;  stat_hits <= s_hits;  stat_misses <= s_miss;
  dbg_cstate <= cst(dbg_node*NB + dbg_blk);
  dbg_cdata  <= cdat(dbg_node*NB + dbg_blk);
  dbg_dstate <= dst(dbg_blk);
  dbg_dsharers <= dsh(dbg_blk);
  dbg_mem    <= mem(dbg_blk);

  decode : process (all)
    variable cv, bv, kv, ov, hv : natural;
    variable wrv, hitv, found : boolean;
    variable csv, dsv : natural;
    variable shv, othv : std_logic_vector(P-1 downto 0);
  begin
    if busy = '1' then cv := r_node; bv := r_blk; wrv := (r_wr = '1'); wd <= r_wdata;
    else               cv := req_node; bv := req_blk; wrv := (req_write = '1'); wd <= req_wdata;
    end if;
    csv := cst(cv*NB + bv);  dsv := dst(bv);  shv := dsh(bv);
    othv := shv;  othv(cv) := '0';
    kv := 0;  ov := 0;  found := false;
    for j in 0 to P-1 loop
      if othv(j) = '1' then kv := kv + 1; end if;
      if shv(j) = '1' and j /= cv then ov := j; found := true; end if;
    end loop;
    hitv := ((not wrv) and csv /= C_I) or (wrv and csv = C_M);
    if not wrv then
      if dsv = D_M then hv := 4; else hv := 2; end if;
    elsif dsv = D_U then hv := 2;
    elsif dsv = D_S then
      if kv = 0 then hv := 2; else hv := 4; end if;
    else hv := 4;
    end if;
    c <= cv;  b <= bv;  wr <= wrv;  cs <= csv;  ds <= dsv;  sh <= shv;  oth <= othv;  k <= kv;  owner <= ov;  hit <= hitv;  hops <= hv;
  end process;

  seq : process (clk, rst_n)
    variable shv : std_logic_vector(P-1 downto 0);
  begin
    if rst_n = '0' then
      busy <= '0';  cnt <= 0;  rv <= '0';  rd <= (others => '0');
      r_node <= 0;  r_wr <= '0';  r_blk <= 0;  r_wdata <= (others => '0');
      s_req <= 0;  s_rep <= 0;  s_inv <= 0;  s_ack <= 0;  s_fetch <= 0;  s_wb <= 0;  s_hits <= 0;  s_miss <= 0;
      cst <= (others => C_I);  cdat <= (others => (others => '0'));  dst <= (others => D_U);  dsh <= (others => (others => '0'));  mem <= init_mem;
    elsif rising_edge(clk) then
      rv <= '0';
      if busy = '0' then
        if req_valid = '1' then
          if hit then                                                      -- a hit never leaves the node
            s_hits <= s_hits + 1;  rv <= '1';
            if wr then cdat(c*NB + b) <= wd; rd <= wd; else rd <= cdat(c*NB + b); end if;
          else                                                             -- a miss starts a transaction of `hops` message hops
            s_miss <= s_miss + 1;
            busy <= '1';  cnt <= hops * LAT;
            r_node <= req_node;  r_wr <= req_write;  r_blk <= req_blk;  r_wdata <= req_wdata;
          end if;
        end if;
      else
        if cnt = 1 then                                                    -- the reply arrives: the transaction completes
          busy <= '0';  cnt <= 0;  rv <= '1';
          s_req <= s_req + 1;  s_rep <= s_rep + 1;
          if not wr then
            if ds = D_M then                                               -- fetch from the owner, which keeps a Shared copy; memory is updated
              s_fetch <= s_fetch + 1;  s_wb <= s_wb + 1;
              mem(b) <= cdat(owner*NB + b);  cst(owner*NB + b) <= C_S;
              cdat(c*NB + b) <= cdat(owner*NB + b);  rd <= cdat(owner*NB + b);
              shv := (others => '0');  shv(owner) := '1';  shv(c) := '1';
              dsh(b) <= shv;
            else
              cdat(c*NB + b) <= mem(b);  rd <= mem(b);
              shv := sh;  shv(c) := '1';
              dsh(b) <= shv;
            end if;
            cst(c*NB + b) <= C_S;  dst(b) <= D_S;
          else
            if ds = D_M then                                               -- fetch + invalidate the owner
              s_fetch <= s_fetch + 1;  s_wb <= s_wb + 1;
              mem(b) <= cdat(owner*NB + b);  cst(owner*NB + b) <= C_I;
            elsif ds = D_S and k > 0 then                                  -- invalidate the other sharers, collect the acknowledgements
              s_inv <= s_inv + k;  s_ack <= s_ack + k;
              for j in 0 to P-1 loop if oth(j) = '1' then cst(j*NB + b) <= C_I; end if; end loop;
            end if;
            cst(c*NB + b) <= C_M;  cdat(c*NB + b) <= wd;  rd <= wd;
            dst(b) <= D_M;
            shv := (others => '0');  shv(c) := '1';
            dsh(b) <= shv;
          end if;
        else
          cnt <= cnt - 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
