-- An NX x NY 2-D mesh of vc_router instances.  Node n = y*NX + x.  Each node has a LOCAL port: flits are injected with inj_valid / inj_flit
-- (the injector must respect the per-VC credits: inj_credit_v / inj_credit_vc return one credit per flit popped; start with DEPTH credits per VC; the vc field of an injected flit selects the VC) and ejected on ej_valid / ej_flit.
-- Router (x,y) output East feeds router (x+1,y) input West (and credits flow back the opposite way); likewise for the other directions.  Mesh edges are tied off.
library ieee;
use ieee.std_logic_1164.all;
use work.vc_pkg.all;

entity vc_net is
  generic (NX : positive := 4; NY : positive := 4; NVC : positive := 2; DEPTH : positive := 4);
  port (
    clk, rst_n   : in  std_logic;
    inj_valid    : in  std_logic_vector(NX*NY-1 downto 0);
    inj_flit     : in  std_logic_vector(NX*NY*FW-1 downto 0);
    inj_credit_v : out std_logic_vector(NX*NY-1 downto 0);
    inj_credit_vc: out std_logic_vector(NX*NY*2-1 downto 0);
    ej_valid     : out std_logic_vector(NX*NY-1 downto 0);
    ej_flit      : out std_logic_vector(NX*NY*FW-1 downto 0);
    err_overflow : out std_logic
  );
end entity;

architecture rtl of vc_net is
  constant NN : positive := NX * NY;
  signal r_in_v, r_cr_in, r_out_v, r_cr_out : std_logic_vector(NN*5-1 downto 0);
  signal r_cr_in_vc, r_cr_out_vc : std_logic_vector(NN*10-1 downto 0);
  signal r_in_f, r_out_f : std_logic_vector(NN*5*FW-1 downto 0);
  signal r_err : std_logic_vector(NN-1 downto 0);
begin
  err_overflow <= '0' when r_err = (r_err'range => '0') else '1';

  row : for gy in 0 to NY-1 generate
    col : for gx in 0 to NX-1 generate
      constant nid : natural := gy * NX + gx;
    begin
      -- ---- inputs: neighbours' outputs (N input <- node above's S output, E <- right's W, S <- below's N, W <- left's E)
      have_n : if gy > 0 generate
        r_in_v(nid*5 + P_N) <= r_out_v((nid - NX)*5 + P_S);
        r_in_f((nid*5 + P_N)*FW + FW-1 downto (nid*5 + P_N)*FW) <= r_out_f(((nid - NX)*5 + P_S)*FW + FW-1 downto ((nid - NX)*5 + P_S)*FW);
        r_cr_in(nid*5 + P_N) <= r_cr_out((nid - NX)*5 + P_S);
        r_cr_in_vc((nid*5 + P_N)*2 + 1 downto (nid*5 + P_N)*2) <= r_cr_out_vc(((nid - NX)*5 + P_S)*2 + 1 downto ((nid - NX)*5 + P_S)*2);
      end generate;
      no_n : if gy = 0 generate
        r_in_v(nid*5 + P_N) <= '0';  r_in_f((nid*5 + P_N)*FW + FW-1 downto (nid*5 + P_N)*FW) <= (others => '0');  r_cr_in(nid*5 + P_N) <= '0';  r_cr_in_vc((nid*5 + P_N)*2 + 1 downto (nid*5 + P_N)*2) <= (others => '0');
      end generate;
      have_e : if gx < NX - 1 generate
        r_in_v(nid*5 + P_E) <= r_out_v((nid + 1)*5 + P_W);
        r_in_f((nid*5 + P_E)*FW + FW-1 downto (nid*5 + P_E)*FW) <= r_out_f(((nid + 1)*5 + P_W)*FW + FW-1 downto ((nid + 1)*5 + P_W)*FW);
        r_cr_in(nid*5 + P_E) <= r_cr_out((nid + 1)*5 + P_W);
        r_cr_in_vc((nid*5 + P_E)*2 + 1 downto (nid*5 + P_E)*2) <= r_cr_out_vc(((nid + 1)*5 + P_W)*2 + 1 downto ((nid + 1)*5 + P_W)*2);
      end generate;
      no_e : if gx = NX - 1 generate
        r_in_v(nid*5 + P_E) <= '0';  r_in_f((nid*5 + P_E)*FW + FW-1 downto (nid*5 + P_E)*FW) <= (others => '0');  r_cr_in(nid*5 + P_E) <= '0';  r_cr_in_vc((nid*5 + P_E)*2 + 1 downto (nid*5 + P_E)*2) <= (others => '0');
      end generate;
      have_s : if gy < NY - 1 generate
        r_in_v(nid*5 + P_S) <= r_out_v((nid + NX)*5 + P_N);
        r_in_f((nid*5 + P_S)*FW + FW-1 downto (nid*5 + P_S)*FW) <= r_out_f(((nid + NX)*5 + P_N)*FW + FW-1 downto ((nid + NX)*5 + P_N)*FW);
        r_cr_in(nid*5 + P_S) <= r_cr_out((nid + NX)*5 + P_N);
        r_cr_in_vc((nid*5 + P_S)*2 + 1 downto (nid*5 + P_S)*2) <= r_cr_out_vc(((nid + NX)*5 + P_N)*2 + 1 downto ((nid + NX)*5 + P_N)*2);
      end generate;
      no_s : if gy = NY - 1 generate
        r_in_v(nid*5 + P_S) <= '0';  r_in_f((nid*5 + P_S)*FW + FW-1 downto (nid*5 + P_S)*FW) <= (others => '0');  r_cr_in(nid*5 + P_S) <= '0';  r_cr_in_vc((nid*5 + P_S)*2 + 1 downto (nid*5 + P_S)*2) <= (others => '0');
      end generate;
      have_w : if gx > 0 generate
        r_in_v(nid*5 + P_W) <= r_out_v((nid - 1)*5 + P_E);
        r_in_f((nid*5 + P_W)*FW + FW-1 downto (nid*5 + P_W)*FW) <= r_out_f(((nid - 1)*5 + P_E)*FW + FW-1 downto ((nid - 1)*5 + P_E)*FW);
        r_cr_in(nid*5 + P_W) <= r_cr_out((nid - 1)*5 + P_E);
        r_cr_in_vc((nid*5 + P_W)*2 + 1 downto (nid*5 + P_W)*2) <= r_cr_out_vc(((nid - 1)*5 + P_E)*2 + 1 downto ((nid - 1)*5 + P_E)*2);
      end generate;
      no_w : if gx = 0 generate
        r_in_v(nid*5 + P_W) <= '0';  r_in_f((nid*5 + P_W)*FW + FW-1 downto (nid*5 + P_W)*FW) <= (others => '0');  r_cr_in(nid*5 + P_W) <= '0';  r_cr_in_vc((nid*5 + P_W)*2 + 1 downto (nid*5 + P_W)*2) <= (others => '0');
      end generate;
      -- ---- local port
      r_in_v(nid*5 + P_L) <= inj_valid(nid);
      r_in_f((nid*5 + P_L)*FW + FW-1 downto (nid*5 + P_L)*FW) <= inj_flit(nid*FW + FW-1 downto nid*FW);
      r_cr_in(nid*5 + P_L) <= '0';  r_cr_in_vc((nid*5 + P_L)*2 + 1 downto (nid*5 + P_L)*2) <= (others => '0');
      inj_credit_v(nid) <= r_cr_out(nid*5 + P_L);  inj_credit_vc(nid*2 + 1 downto nid*2) <= r_cr_out_vc((nid*5 + P_L)*2 + 1 downto (nid*5 + P_L)*2);
      ej_valid(nid) <= r_out_v(nid*5 + P_L);
      ej_flit(nid*FW + FW-1 downto nid*FW) <= r_out_f((nid*5 + P_L)*FW + FW-1 downto (nid*5 + P_L)*FW);

      u_r : entity work.vc_router
        generic map (X => gx, Y => gy, NX => NX, NY => NY, NVC => NVC, DEPTH => DEPTH)
        port map (clk => clk, rst_n => rst_n,
                  in_valid => r_in_v(nid*5 + 4 downto nid*5), in_flit => r_in_f(nid*5*FW + 5*FW-1 downto nid*5*FW),
                  in_credit_v => r_cr_out(nid*5 + 4 downto nid*5), in_credit_vc => r_cr_out_vc(nid*10 + 9 downto nid*10),
                  out_valid => r_out_v(nid*5 + 4 downto nid*5), out_flit => r_out_f(nid*5*FW + 5*FW-1 downto nid*5*FW),
                  out_credit_v => r_cr_in(nid*5 + 4 downto nid*5), out_credit_vc => r_cr_in_vc(nid*10 + 9 downto nid*10), err_overflow => r_err(nid));
    end generate;
  end generate;
end architecture;
