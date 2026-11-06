-- N x N crossbar switch with a round-robin arbiter on every output (Appendix F).
-- Each input presents (req, dst, data).  Every output independently picks one of the inputs
-- that want it; the pointer moves just past the last winner, so under contention the winners
-- rotate fairly and no input can be starved.  Inputs aimed at different outputs are all served
-- in the same cycle (that is what a crossbar buys you over a shared bus).  An input whose
-- request loses arbitration sees in_gnt = 0 and must retry (head-of-line blocking).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rr_crossbar is
  generic (N : positive := 4; W : positive := 32; DW : positive := 2);   -- DW = log2(N)
  port (
    clk, rst_n : in  std_logic;
    in_req     : in  std_logic_vector(N-1 downto 0);
    in_dst     : in  std_logic_vector(N*DW-1 downto 0);     -- destination output of each input
    in_data    : in  std_logic_vector(N*W-1 downto 0);
    in_gnt     : out std_logic_vector(N-1 downto 0);        -- input i's flit was accepted this cycle
    out_valid  : out std_logic_vector(N-1 downto 0);
    out_src    : out std_logic_vector(N*DW-1 downto 0);     -- which input won each output
    out_data   : out std_logic_vector(N*W-1 downto 0)
  );
end entity;

architecture rtl of rr_crossbar is
  type ptr_t is array (0 to N-1) of natural range 0 to N-1;
  signal ptr   : ptr_t := (others => N-1);                  -- per output: last winner
  signal win   : ptr_t;
  signal found : std_logic_vector(N-1 downto 0);
begin
  arb : process (all)
    variable idx : natural;
    variable f   : boolean;
    variable wn  : natural range 0 to N-1;
    variable gnt : std_logic_vector(N-1 downto 0);
  begin
    gnt := (others => '0');
    for j in 0 to N-1 loop
      f := false;  wn := 0;
      for k in 1 to N loop
        idx := (ptr(j) + k) mod N;
        if not f and in_req(idx) = '1' and to_integer(unsigned(in_dst(idx*DW + DW-1 downto idx*DW))) = j then
          f := true;  wn := idx;
        end if;
      end loop;
      win(j) <= wn;
      if f then found(j) <= '1'; else found(j) <= '0'; end if;
      out_valid(j) <= '1' when f else '0';
      out_src(j*DW + DW-1 downto j*DW) <= std_logic_vector(to_unsigned(wn, DW));
      if f then
        out_data(j*W + W-1 downto j*W) <= in_data(wn*W + W-1 downto wn*W);
        gnt(wn) := '1';
      else
        out_data(j*W + W-1 downto j*W) <= (others => '0');
      end if;
    end loop;
    in_gnt <= gnt;
  end process;

  seq : process (clk, rst_n)
  begin
    if rst_n = '0' then
      ptr <= (others => N-1);                               -- first winner will be input 0
    elsif rising_edge(clk) then
      for j in 0 to N-1 loop
        if found(j) = '1' then ptr(j) <= win(j); end if;
      end loop;
    end if;
  end process;
end architecture;
