-- A VIRTUAL-CHANNEL wormhole router (Appendix F: virtual channels, VC allocation, switch allocation).
--
-- Every input port has NVC virtual channels: NVC separate flit FIFOs (DEPTH flits each) that share the one physical link.  A packet occupies ONE virtual channel
-- per hop from head to tail, but the flits of packets in different virtual channels are interleaved on the link, flit by flit.  Consequence: a packet that is blocked
-- (its output is busy or has no credits) no longer blocks the packets queued behind it in OTHER virtual channels -- no head-of-line blocking.
--
--   * ROUTING: dimension-order (XY), as in mesh_router.
--   * VC ALLOCATION (VA): the head flit of a packet at the front of an idle input VC asks for an output port; each output port grants one request per cycle (round-robin) and
--     gives the winner the lowest FREE output VC (a VC is free from the head's grant until the tail has been sent).  A head therefore spends one extra cycle in the router.
--   * SWITCH ALLOCATION (SA): separable, two stages.  Each input port picks (round-robin) one of its VCs that has an allocated output VC, a flit and a CREDIT for the downstream
--     VC buffer; each output port then picks (round-robin) one of the input ports that chose it.  The winning flit is moved into the output register with its vc field rewritten
--     to the output VC.
--   * FLOW CONTROL: one credit counter per output VC (initially DEPTH); a credit pulse carries the VC number (in_credit_v / in_credit_vc: one pop per input port per cycle).
--     The Local (ejection) output needs no credits.
-- Pipeline: a head flit written to an input FIFO at the end of cycle c wins VA in c+1, SA in c+2 and is on the output link during c+3: THREE cycles per router.  Body and tail
-- flits need only SA: two cycles.  The credit round trip per VC is four cycles, as in mesh_router, so DEPTH = 4 per VC sustains one flit per cycle for a single stream.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.vc_pkg.all;

entity vc_router is
  generic (X : natural := 0; Y : natural := 0; NX : positive := 4; NY : positive := 4; NVC : positive := 2; DEPTH : positive := 4);
  port (
    clk, rst_n   : in  std_logic;
    in_valid     : in  std_logic_vector(4 downto 0);
    in_flit      : in  std_logic_vector(5*FW-1 downto 0);
    in_credit_v  : out std_logic_vector(4 downto 0);        -- pulse: a flit left an input FIFO of port p ...
    in_credit_vc : out std_logic_vector(9 downto 0);        -- ... of this virtual channel (2 bits per port)
    out_valid    : out std_logic_vector(4 downto 0);
    out_flit     : out std_logic_vector(5*FW-1 downto 0);
    out_credit_v : in  std_logic_vector(4 downto 0);        -- pulses from the downstream routers
    out_credit_vc: in  std_logic_vector(9 downto 0);
    err_overflow : out std_logic                             -- sticky: an input FIFO was written while full (flow-control violation)
  );
end entity;

architecture rtl of vc_router is
  constant NIV : positive := 5 * NVC;                         -- input virtual channels, index p*NVC + v
  subtype flit_t is std_logic_vector(FW-1 downto 0);
  type flit_arr is array (natural range <>) of flit_t;
  type nat_arr  is array (natural range <>) of natural;

  signal fifo : flit_arr(0 to NIV*DEPTH-1) := (others => (others => '0'));
  signal rd, wr, cnt, st_op, st_ov, cred : nat_arr(0 to NIV-1) := (others => 0);
  signal st_act, ovb : std_logic_vector(0 to NIV-1) := (others => '0');
  signal va_rr, sa_in_rr, sa_out_rr : nat_arr(0 to 4) := (others => 0);
  signal out_valid_i, in_credit_v_i : std_logic_vector(4 downto 0) := (others => '0');
  signal out_flit_i : std_logic_vector(5*FW-1 downto 0) := (others => '0');
  signal in_credit_vc_i : std_logic_vector(9 downto 0) := (others => '0');
  signal err_i : std_logic := '0';
  -- combinational results
  signal hf : flit_arr(0 to NIV-1);
  signal it_s, fwd : std_logic_vector(0 to NIV-1);
  signal va_v, win_v : std_logic_vector(0 to 4);
  signal fwd_p : std_logic_vector(4 downto 0);                 -- same index order as in_credit_v
  signal va_iv, va_ov, win_iv, win_p : nat_arr(0 to 4);
begin
  out_valid <= out_valid_i;  out_flit <= out_flit_i;  in_credit_v <= in_credit_v_i;  in_credit_vc <= in_credit_vc_i;  err_overflow <= err_i;

  comb : process (all)
    variable hfv : flit_t;
    variable ty : std_logic_vector(1 downto 0);
    variable ne, ih, it : std_logic_vector(0 to NIV-1);
    variable rt : nat_arr(0 to NIV-1);
    variable dxv, dyv, pk, fo, qv, qp : natural;
    variable fo_ok : boolean;
    variable vv, wv, cv : std_logic_vector(0 to 4);
    variable fp : std_logic_vector(4 downto 0);
    variable viv, vov, wiv, wp, civ : nat_arr(0 to 4);
    variable fw_v : std_logic_vector(0 to NIV-1);
  begin
    for i in 0 to NIV-1 loop
      hfv := fifo(i*DEPTH + rd(i));
      hf(i) <= hfv;
      ty := hfv(FW-1 downto FW-2);
      if cnt(i) /= 0 then ne(i) := '1'; else ne(i) := '0'; end if;
      if ty = T_HEAD or ty = T_SINGLE then ih(i) := '1'; else ih(i) := '0'; end if;
      if ty = T_TAIL or ty = T_SINGLE then it(i) := '1'; else it(i) := '0'; end if;
      dxv := to_integer(unsigned(hfv(27 downto 24)));  dyv := to_integer(unsigned(hfv(31 downto 28)));
      if    dxv > X then rt(i) := P_E;
      elsif dxv < X then rt(i) := P_W;
      elsif dyv > Y then rt(i) := P_S;
      elsif dyv < Y then rt(i) := P_N;
      else rt(i) := P_L;
      end if;
    end loop;
    -- VC allocation: one grant per output port per cycle
    for o in 0 to 4 loop
      vv(o) := '0';  viv(o) := 0;  vov(o) := 0;
      fo_ok := false;  fo := 0;
      for ov in NVC-1 downto 0 loop if ovb(o*NVC + ov) = '0' then fo_ok := true; fo := ov; end if; end loop;
      if fo_ok then
        for k in 1 to NIV loop
          pk := (va_rr(o) + k) mod NIV;
          if vv(o) = '0' and ne(pk) = '1' and st_act(pk) = '0' and ih(pk) = '1' and rt(pk) = o then vv(o) := '1'; viv(o) := pk; vov(o) := fo; end if;
        end loop;
      end if;
    end loop;
    -- switch allocation, input stage
    for p in 0 to 4 loop
      cv(p) := '0';  civ(p) := 0;
      for k in 1 to NVC loop
        qv := (sa_in_rr(p) + k) mod NVC;
        if cv(p) = '0' and st_act(p*NVC + qv) = '1' and ne(p*NVC + qv) = '1' and (st_op(p*NVC + qv) = P_L or cred(st_op(p*NVC + qv)*NVC + st_ov(p*NVC + qv)) /= 0) then
          cv(p) := '1';  civ(p) := p*NVC + qv;
        end if;
      end loop;
    end loop;
    -- output stage
    for o in 0 to 4 loop
      wv(o) := '0';  wiv(o) := 0;  wp(o) := 0;
      for k in 1 to 5 loop
        qp := (sa_out_rr(o) + k) mod 5;
        if wv(o) = '0' and cv(qp) = '1' and st_op(civ(qp)) = o then wv(o) := '1'; wiv(o) := civ(qp); wp(o) := qp; end if;
      end loop;
    end loop;
    fp := (others => '0');  fw_v := (others => '0');
    for o in 0 to 4 loop if wv(o) = '1' then fw_v(wiv(o)) := '1'; fp(wp(o)) := '1'; end if; end loop;
    va_v <= vv;  va_iv <= viv;  va_ov <= vov;  win_v <= wv;  win_iv <= wiv;  win_p <= wp;  fwd_p <= fp;  fwd <= fw_v;  it_s <= it;
  end process;

  seq : process (clk, rst_n)
    variable sf : flit_t;
    variable w, ivx, vc, ovx : natural;
    variable dec_c, inc_c, wr_i : boolean;
    variable ci : std_logic_vector(9 downto 0);
  begin
    if rst_n = '0' then
      out_valid_i <= (others => '0');  out_flit_i <= (others => '0');  in_credit_v_i <= (others => '0');  in_credit_vc_i <= (others => '0');  err_i <= '0';
      rd <= (others => 0);  wr <= (others => 0);  cnt <= (others => 0);  st_act <= (others => '0');  st_op <= (others => 0);  st_ov <= (others => 0);
      ovb <= (others => '0');  cred <= (others => DEPTH);
      va_rr <= (others => NIV - 1);  sa_in_rr <= (others => NVC - 1);  sa_out_rr <= (others => 4);
      fifo <= (others => (others => '0'));
    elsif rising_edge(clk) then
      -- VC allocation results
      for o in 0 to 4 loop
        if va_v(o) = '1' then
          st_act(va_iv(o)) <= '1';  st_op(va_iv(o)) <= o;  st_ov(va_iv(o)) <= va_ov(o);
          ovb(o*NVC + va_ov(o)) <= '1';  va_rr(o) <= va_iv(o);
        end if;
      end loop;
      -- switch allocation results: the flit moves into the output register
      for o in 0 to 4 loop
        out_valid_i(o) <= win_v(o);
        if win_v(o) = '1' then
          ivx := win_iv(o);
          sf := hf(ivx);  sf(33 downto 32) := std_logic_vector(to_unsigned(st_ov(ivx), 2));
          out_flit_i(o*FW + FW-1 downto o*FW) <= sf;
          sa_out_rr(o) <= win_p(o);
          sa_in_rr(win_p(o)) <= ivx mod NVC;
          if it_s(ivx) = '1' then
            st_act(ivx) <= '0';  ovb(o*NVC + st_ov(ivx)) <= '0';
          end if;
        end if;
      end loop;
      -- credit counters, one per output VC
      for o in 0 to 4 loop
        for ov in 0 to NVC-1 loop
          dec_c := (o /= P_L) and win_v(o) = '1' and st_ov(win_iv(o)) = ov;
          inc_c := out_credit_v(o) = '1' and to_integer(unsigned(out_credit_vc(2*o + 1 downto 2*o))) = ov;
          if dec_c and not inc_c then cred(o*NVC + ov) <= cred(o*NVC + ov) - 1;
          elsif inc_c and not dec_c then cred(o*NVC + ov) <= cred(o*NVC + ov) + 1;
          end if;
        end loop;
      end loop;
      -- credit pulses for the upstream routers
      ci := (others => '0');
      for o in 0 to 4 loop if win_v(o) = '1' then ci(2*win_p(o) + 1 downto 2*win_p(o)) := std_logic_vector(to_unsigned(win_iv(o) mod NVC, 2)); end if; end loop;
      in_credit_v_i <= fwd_p;  in_credit_vc_i <= ci;
      -- input FIFOs
      for p in 0 to 4 loop
        if in_valid(p) = '1' then
          vc := to_integer(unsigned(in_flit(p*FW + 33 downto p*FW + 32)));
          if vc < NVC then fifo((p*NVC + vc)*DEPTH + wr(p*NVC + vc)) <= in_flit(p*FW + FW-1 downto p*FW); end if;
        end if;
      end loop;
      for i in 0 to NIV-1 loop
        wr_i := false;
        if in_valid(i / NVC) = '1' and to_integer(unsigned(in_flit((i / NVC)*FW + 33 downto (i / NVC)*FW + 32))) = i mod NVC then wr_i := true; end if;
        if wr_i then
          if wr(i) = DEPTH - 1 then wr(i) <= 0; else wr(i) <= wr(i) + 1; end if;
          if cnt(i) = DEPTH then err_i <= '1'; end if;
        end if;
        if fwd(i) = '1' then
          if rd(i) = DEPTH - 1 then rd(i) <= 0; else rd(i) <= rd(i) + 1; end if;
        end if;
        if wr_i and fwd(i) = '0' then cnt(i) <= cnt(i) + 1;
        elsif (not wr_i) and fwd(i) = '1' then cnt(i) <= cnt(i) - 1;
        end if;
      end loop;
    end if;
  end process;
end architecture;
