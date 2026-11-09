-- Atomic read-modify-write and spin locks on a snooping bus (Chapter 5: synchronization).
--
-- P cores share a write-invalidate (MSI) snooping bus.  Each core repeats N times:   acquire the lock; critical section = { load counter, CS_LEN cycles of work, store counter+1 };
-- release; think NT cycles.  Three locks, selected by LOCK:
--   0 TAS     test-and-set: spin on an ATOMIC EXCHANGE (xchg L,1) until it returns 0.  Every attempt needs the line in M, so contending cores steal it from each other: bus traffic per spin.
--   1 TTAS    test-and-test-and-set: spin with plain LOADS (the line stays Shared in every spinner's cache: no bus traffic) and issue the atomic exchange only when the lock reads 0.
--   2 TICKET  ticket lock: FETCH-AND-ADD on the ticket counter gives each core a number; spin with loads on now_serving until it equals the number; release stores number+1 (FIFO order).
--   3 NONE    no lock (a control: the critical sections overlap and increments are lost).
-- Memory system: 3 lines (0 = lock / next ticket, 1 = now serving, 2 = counter).  Coherence STATES (I/S/M) of every line in every cache decide the bus traffic; the VALUES live in one coherent
-- memory image, and a memory operation performs atomically at the cycle it hits in the cache or completes on the bus.
--   * An operation that HITS (LD in S or M, ST / atomic in M) takes 1 cycle and no bus traffic.
--   * A miss (LD in I -> BusRd; ST / atomic in I or S -> BusRdX / upgrade) arbitrates for the bus (round robin).  A transaction takes BUS_LAT cycles: the coherence actions happen when it is
--     GRANTED (BusRd: owner M -> S, requester S; BusRdX: every other copy -> I, requester M) and the operation performs when it completes, BUS_LAT-1 cycles after the grant.
--   * An uncontended miss therefore takes BUS_LAT cycles in all.
-- Statistics: stat_rd / stat_rdx (bus transactions by kind), stat_cycles (cycles until every core is done), counter value, the maximum number of cores inside the critical section at once,
-- and per-core acquisition / ticket pulses for the FIFO check.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity spinlock_bench is
  generic (P : positive := 4; N : positive := 4; LOCK : natural := 0; BUS_LAT : positive := 4; CS_LEN : natural := 2; NT : natural := 3);
  port (
    clk, rst_n  : in  std_logic;
    done        : out std_logic;
    stat_rd, stat_rdx, stat_cycles : out natural;
    counter     : out natural;
    cs_count    : out natural;                          -- cores inside the critical section right now
    acq_pulse   : out std_logic_vector(P-1 downto 0);   -- core k acquired the lock (one cycle)
    tick_pulse  : out std_logic_vector(P-1 downto 0)    -- core k drew a ticket (one cycle)
  );
end entity;

architecture rtl of spinlock_bench is
  constant NL : positive := 3;
  constant S_THINK : natural := 0;  constant S_ACQ : natural := 1;  constant S_TT_RD : natural := 2;  constant S_TT_X : natural := 3;  constant S_TK_FAA : natural := 4;
  constant S_TK_SPIN : natural := 5;  constant S_C_LD : natural := 6;  constant S_WORK : natural := 7;  constant S_C_ST : natural := 8;  constant S_REL : natural := 9;  constant S_DONE : natural := 10;
  constant M_I : natural := 0;  constant M_S : natural := 1;  constant M_M : natural := 2;
  function first_state return natural is
  begin
    if LOCK = 0 then return S_ACQ; elsif LOCK = 1 then return S_TT_RD; elsif LOCK = 2 then return S_TK_FAA; else return S_C_LD; end if;
  end function;
  constant FIRST : natural := first_state;
  type nat_t is array (natural range <>) of natural;

  signal fs, cnt, itn, my, tmp : nat_t(0 to P-1) := (others => 0);
  signal in_cs : std_logic_vector(0 to P-1) := (others => '0');
  signal cst : nat_t(0 to P*NL-1) := (others => M_I);
  signal val : nat_t(0 to NL-1) := (others => 0);
  signal busy : std_logic := '0';
  signal owner, rcnt, rr : natural := 0;
  signal s_rd, s_rdx, s_cycles : natural := 0;
  signal acq_i, tick_i : std_logic_vector(P-1 downto 0) := (others => '0');
  -- the memory operation each core wants to perform this cycle
  signal opv, hit, want : std_logic_vector(0 to P-1);
  signal opt, opl : nat_t(0 to P-1);
  signal grant : integer range -1 to P-1;
  signal done_i : std_logic;
begin
  stat_rd <= s_rd;  stat_rdx <= s_rdx;  stat_cycles <= s_cycles;  counter <= val(2);  acq_pulse <= acq_i;  tick_pulse <= tick_i;  done <= done_i;

  comb : process (all)
    variable ov : std_logic_vector(0 to P-1);
    variable ot, ol : nat_t(0 to P-1);
    variable h, w : std_logic_vector(0 to P-1);
    variable g, n_cs : integer;
    variable all_done : boolean;
  begin
    for k in 0 to P-1 loop
      ov(k) := '1';  ot(k) := 0;  ol(k) := 0;
      case fs(k) is
        when S_ACQ     => ot(k) := 2; ol(k) := 0;
        when S_TT_RD   => ot(k) := 0; ol(k) := 0;
        when S_TT_X    => ot(k) := 2; ol(k) := 0;
        when S_TK_FAA  => ot(k) := 2; ol(k) := 0;
        when S_TK_SPIN => ot(k) := 0; ol(k) := 1;
        when S_C_LD    => ot(k) := 0; ol(k) := 2;
        when S_C_ST    => ot(k) := 1; ol(k) := 2;
        when S_REL     => ot(k) := 1; if LOCK = 2 then ol(k) := 1; else ol(k) := 0; end if;
        when others    => ov(k) := '0';
      end case;
      if ot(k) = 0 then
        if cst(k*NL + ol(k)) /= M_I then h(k) := '1'; else h(k) := '0'; end if;
      else
        if cst(k*NL + ol(k)) = M_M then h(k) := '1'; else h(k) := '0'; end if;
      end if;
      if ov(k) = '1' and h(k) = '0' and not (busy = '1' and owner = k) then w(k) := '1'; else w(k) := '0'; end if;
    end loop;
    g := -1;
    if busy = '0' then
      for j in 1 to P loop
        if g < 0 and w((rr + j) mod P) = '1' then g := (rr + j) mod P; end if;
      end loop;
    end if;
    n_cs := 0;
    for k in 0 to P-1 loop if in_cs(k) = '1' then n_cs := n_cs + 1; end if; end loop;
    all_done := true;
    for k in 0 to P-1 loop if fs(k) /= S_DONE then all_done := false; end if; end loop;
    opv <= ov;  opt <= ot;  opl <= ol;  hit <= h;  want <= w;  grant <= g;  cs_count <= n_cs;
    if all_done then done_i <= '1'; else done_i <= '0'; end if;
  end process;

  seq : process (clk, rst_n)
    procedure next_iter(k : natural) is
    begin
      itn(k) <= itn(k) + 1;
      if itn(k) + 1 >= N then fs(k) <= S_DONE;
      elsif NT > 0 then fs(k) <= S_THINK; cnt(k) <= NT;
      else
        fs(k) <= FIRST;
        if LOCK = 3 then in_cs(k) <= '1'; end if;
      end if;
    end procedure;
    procedure perform(k : natural) is
      variable old : natural;
      variable ln : natural;
    begin
      ln := opl(k);  old := val(ln);
      case fs(k) is
        when S_ACQ =>                                               -- xchg(L, 1)
          val(0) <= 1;
          if old = 0 then fs(k) <= S_C_LD; in_cs(k) <= '1'; acq_i(k) <= '1'; end if;
        when S_TT_RD => if old = 0 then fs(k) <= S_TT_X; end if;
        when S_TT_X =>
          val(0) <= 1;
          if old = 0 then fs(k) <= S_C_LD; in_cs(k) <= '1'; acq_i(k) <= '1'; else fs(k) <= S_TT_RD; end if;
        when S_TK_FAA => val(0) <= old + 1; my(k) <= old; fs(k) <= S_TK_SPIN; tick_i(k) <= '1';
        when S_TK_SPIN => if old = my(k) then fs(k) <= S_C_LD; in_cs(k) <= '1'; acq_i(k) <= '1'; end if;
        when S_C_LD =>
          tmp(k) <= old;
          if CS_LEN > 0 then fs(k) <= S_WORK; cnt(k) <= CS_LEN; else fs(k) <= S_C_ST; end if;
        when S_C_ST =>
          val(2) <= tmp(k) + 1;
          if LOCK = 3 then in_cs(k) <= '0'; next_iter(k); else fs(k) <= S_REL; end if;
        when S_REL =>
          if LOCK = 2 then val(1) <= my(k) + 1; else val(0) <= 0; end if;
          in_cs(k) <= '0';
          next_iter(k);
        when others => null;
      end case;
    end procedure;
  begin
    if rst_n = '0' then
      busy <= '0';  owner <= 0;  rcnt <= 0;  rr <= P - 1;
      s_rd <= 0;  s_rdx <= 0;  s_cycles <= 0;  acq_i <= (others => '0');  tick_i <= (others => '0');
      fs <= (others => FIRST);  cnt <= (others => 0);  itn <= (others => 0);  my <= (others => 0);  tmp <= (others => 0);
      if LOCK = 3 then in_cs <= (others => '1'); else in_cs <= (others => '0'); end if;
      cst <= (others => M_I);  val <= (others => 0);
    elsif rising_edge(clk) then
      acq_i <= (others => '0');  tick_i <= (others => '0');
      if done_i = '0' then s_cycles <= s_cycles + 1; end if;
      -- cores: think / work counters, and operations that hit
      for k in 0 to P-1 loop
        if fs(k) = S_THINK then
          if cnt(k) <= 1 then fs(k) <= FIRST; if LOCK = 3 then in_cs(k) <= '1'; end if; else cnt(k) <= cnt(k) - 1; end if;
        elsif fs(k) = S_WORK then
          if cnt(k) <= 1 then fs(k) <= S_C_ST; else cnt(k) <= cnt(k) - 1; end if;
        elsif opv(k) = '1' and hit(k) = '1' and not (busy = '1' and owner = k) then
          perform(k);
        end if;
      end loop;
      -- the bus: complete the transaction in flight, or grant a new one
      if busy = '1' then
        if rcnt = 1 then busy <= '0'; perform(owner);
        else rcnt <= rcnt - 1; end if;
      elsif grant >= 0 then
        busy <= '1';  owner <= grant;  rcnt <= BUS_LAT - 1;  rr <= grant;
        if opt(grant) = 0 then
          s_rd <= s_rd + 1;
          for j in 0 to P-1 loop if j /= grant and cst(j*NL + opl(grant)) = M_M then cst(j*NL + opl(grant)) <= M_S; end if; end loop;
          cst(grant*NL + opl(grant)) <= M_S;
        else
          s_rdx <= s_rdx + 1;
          for j in 0 to P-1 loop if j /= grant then cst(j*NL + opl(grant)) <= M_I; end if; end loop;
          cst(grant*NL + opl(grant)) <= M_M;
        end if;
      end if;
    end if;
  end process;
end architecture;
