-- A wormhole-switched 5-port mesh router (Appendix F: routing, flow control, arbitration).
--
--   * Ports 0..4 = North, East, South, West, Local.  Router (X,Y) sits at column X, row Y of an NX x NY mesh (y grows southward).
--   * ROUTING: dimension-order (XY): correct X first (East/West) until dest_x = X, then Y (South/North), then eject on the Local port.
--     XY routing is minimal and deadlock-free on a mesh (no packet ever turns from the Y dimension back into X).
--   * WORMHOLE: a packet is a head flit (carries the destination), body flits and a tail.  The head claims an output port; the port stays
--     LOCKED to that input until the tail has passed, so the flits of different packets never interleave on a link.
--   * FLOW CONTROL is credit based.  Each output keeps a counter of free slots in the downstream input FIFO (initially DEPTH).  A flit may be
--     forwarded only if a credit is available; the counter is decremented when the flit is sent and incremented when the downstream router pops
--     it and returns a one-cycle credit pulse.  (The Local output ejects into the node and needs no credits.)  Input FIFOs therefore never overflow.
--   * ARBITRATION: an unlocked output picks, round-robin, among the inputs whose head flit is a packet head routed to it.
-- Pipeline (zero load): a flit written to an input FIFO at the end of cycle c is forwarded (switched into the output register) at the end of
-- cycle c+1 and is on the output link during cycle c+2, i.e. TWO cycles per router.  The credit round trip (decision -> pop -> pulse -> counter
-- update -> next decision) is FOUR cycles, so a FIFO depth of 4 is exactly what is needed to sustain one flit per cycle per link.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mesh_pkg.all;

entity mesh_router is
  generic (X : natural := 0; Y : natural := 0; NX : positive := 4; NY : positive := 4; DEPTH : positive := 4);
  port (
    clk, rst_n   : in  std_logic;
    in_valid     : in  std_logic_vector(4 downto 0);
    in_flit      : in  std_logic_vector(5*FW-1 downto 0);
    in_credit    : out std_logic_vector(4 downto 0);        -- pulse: a flit left input FIFO p -> credit for the upstream router
    out_valid    : out std_logic_vector(4 downto 0);
    out_flit     : out std_logic_vector(5*FW-1 downto 0);
    out_credit   : in  std_logic_vector(4 downto 0);        -- pulse from the downstream router
    err_overflow : out std_logic                             -- sticky: an input FIFO was written while full (flow-control violation)
  );
end entity;

architecture rtl of mesh_router is
  subtype flit_t is std_logic_vector(FW-1 downto 0);
  type flit_arr is array (natural range <>) of flit_t;
  type nat_arr  is array (natural range <>) of natural;

  signal fifo : flit_arr(0 to 5*DEPTH-1) := (others => (others => '0'));
  signal rd, wr, cnt, lock_o, owner, cred, rr : nat_arr(0 to 4) := (others => 0);
  signal act, busy : std_logic_vector(0 to 4) := (others => '0');
  signal out_valid_i, in_credit_i : std_logic_vector(4 downto 0) := (others => '0');
  signal out_flit_i : std_logic_vector(5*FW-1 downto 0) := (others => '0');
  signal err_i : std_logic := '0';
  -- combinational results
  signal hf : flit_arr(0 to 4);
  signal win_v, win_new, fwd, is_tail_s : std_logic_vector(0 to 4);
  signal win_p : nat_arr(0 to 4);
begin
  out_valid <= out_valid_i;  out_flit <= out_flit_i;  in_credit <= in_credit_i;  err_overflow <= err_i;

  comb : process (all)
    variable hfv : flit_t;
    variable ty : std_logic_vector(1 downto 0);
    variable ne, ih, it, cok, wv, wn, fv : std_logic_vector(0 to 4);
    variable rt, wp : nat_arr(0 to 4);
    variable pp, dxv, dyv : natural;
  begin
    for p in 0 to 4 loop
      hfv := fifo(p*DEPTH + rd(p));
      hf(p) <= hfv;
      ty := hfv(FW-1 downto FW-2);
      if cnt(p) /= 0 then ne(p) := '1'; else ne(p) := '0'; end if;
      if ty = T_HEAD or ty = T_SINGLE then ih(p) := '1'; else ih(p) := '0'; end if;
      if ty = T_TAIL or ty = T_SINGLE then it(p) := '1'; else it(p) := '0'; end if;
      dxv := to_integer(unsigned(hfv(27 downto 24)));  dyv := to_integer(unsigned(hfv(31 downto 28)));
      if    dxv > X then rt(p) := P_E;
      elsif dxv < X then rt(p) := P_W;
      elsif dyv > Y then rt(p) := P_S;
      elsif dyv < Y then rt(p) := P_N;
      else rt(p) := P_L;
      end if;
    end loop;
    for o in 0 to 4 loop
      if o = P_L or cred(o) /= 0 then cok(o) := '1'; else cok(o) := '0'; end if;
    end loop;
    for o in 0 to 4 loop
      wv(o) := '0';  wp(o) := 0;  wn(o) := '0';
      if busy(o) = '1' then
        if ne(owner(o)) = '1' and cok(o) = '1' then wv(o) := '1'; wp(o) := owner(o); end if;
      elsif cok(o) = '1' then
        for k in 1 to 5 loop
          pp := (rr(o) + k) mod 5;
          if wv(o) = '0' and ne(pp) = '1' and act(pp) = '0' and ih(pp) = '1' and rt(pp) = o then wv(o) := '1'; wp(o) := pp; wn(o) := '1'; end if;
        end loop;
      end if;
    end loop;
    for p in 0 to 4 loop
      fv(p) := '0';
      for o in 0 to 4 loop if wv(o) = '1' and wp(o) = p then fv(p) := '1'; end if; end loop;
    end loop;
    win_v <= wv;  win_p <= wp;  win_new <= wn;  fwd <= fv;  is_tail_s <= it;
  end process;

  seq : process (clk, rst_n)
    variable w : natural range 0 to 4;
  begin
    if rst_n = '0' then
      out_valid_i <= (others => '0');  out_flit_i <= (others => '0');  in_credit_i <= (others => '0');  err_i <= '0';
      rd <= (others => 0);  wr <= (others => 0);  cnt <= (others => 0);  lock_o <= (others => 0);  owner <= (others => 0);
      act <= (others => '0');  busy <= (others => '0');  cred <= (others => DEPTH);  rr <= (others => 4);
      fifo <= (others => (others => '0'));
    elsif rising_edge(clk) then
      -- outputs: a flit moves from its input FIFO into the output register
      for o in 0 to 4 loop
        out_valid_i(o) <= win_v(o);
        if win_v(o) = '1' then
          w := win_p(o);
          out_flit_i(o*FW + FW-1 downto o*FW) <= hf(w);
          if win_new(o) = '1' then
            rr(o) <= w;
            if is_tail_s(w) = '0' then busy(o) <= '1'; owner(o) <= w; act(w) <= '1'; lock_o(w) <= o; end if;
          elsif is_tail_s(w) = '1' then                          -- tail of a locked packet: release the output
            busy(o) <= '0';  act(w) <= '0';
          end if;
        end if;
        -- credit counter: -1 when a flit is sent, +1 when the downstream router returns a credit
        if o /= P_L then
          if win_v(o) = '1' and out_credit(o) = '0' then cred(o) <= cred(o) - 1;
          elsif win_v(o) = '0' and out_credit(o) = '1' then cred(o) <= cred(o) + 1;
          end if;
        end if;
      end loop;
      -- input FIFOs
      for p in 0 to 4 loop
        in_credit_i(p) <= fwd(p);
        if in_valid(p) = '1' then
          fifo(p*DEPTH + wr(p)) <= in_flit(p*FW + FW-1 downto p*FW);
          if wr(p) = DEPTH - 1 then wr(p) <= 0; else wr(p) <= wr(p) + 1; end if;
          if cnt(p) = DEPTH then err_i <= '1'; end if;
        end if;
        if fwd(p) = '1' then
          if rd(p) = DEPTH - 1 then rd(p) <= 0; else rd(p) <= rd(p) + 1; end if;
        end if;
        if in_valid(p) = '1' and fwd(p) = '0' then cnt(p) <= cnt(p) + 1;
        elsif in_valid(p) = '0' and fwd(p) = '1' then cnt(p) <= cnt(p) - 1;
        end if;
      end loop;
    end if;
  end process;
end architecture;
