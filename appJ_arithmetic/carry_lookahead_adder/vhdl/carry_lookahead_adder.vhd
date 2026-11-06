-- 16-bit two-level carry-lookahead adder (Appendix J).
-- Level 1: each 4-bit block computes its own carries by lookahead and exports group G/P.
-- Level 2: a lookahead unit computes the block carry-ins from the group G/P in parallel
--          (no carry ripples between blocks).
library ieee;
use ieee.std_logic_1164.all;

entity cla4_block is
  port (a, b : in std_logic_vector(3 downto 0); cin : in std_logic;
        sum : out std_logic_vector(3 downto 0); g_grp, p_grp : out std_logic);
end entity;

architecture rtl of cla4_block is
  signal g, p : std_logic_vector(3 downto 0);
  signal c1, c2, c3 : std_logic;
begin
  g <= a and b;
  p <= a xor b;
  c1 <= g(0) or (p(0) and cin);
  c2 <= g(1) or (p(1) and g(0)) or (p(1) and p(0) and cin);
  c3 <= g(2) or (p(2) and g(1)) or (p(2) and p(1) and g(0)) or (p(2) and p(1) and p(0) and cin);
  sum <= p xor (c3 & c2 & c1 & cin);
  g_grp <= g(3) or (p(3) and g(2)) or (p(3) and p(2) and g(1)) or (p(3) and p(2) and p(1) and g(0));
  p_grp <= p(3) and p(2) and p(1) and p(0);
end architecture;

library ieee;
use ieee.std_logic_1164.all;

entity carry_lookahead_adder is
  port (a, b : in std_logic_vector(15 downto 0); cin : in std_logic;
        sum : out std_logic_vector(15 downto 0); cout : out std_logic);
end entity;

architecture rtl of carry_lookahead_adder is
  signal G, P, c : std_logic_vector(3 downto 0);
begin
  c(0) <= cin;
  c(1) <= G(0) or (P(0) and cin);
  c(2) <= G(1) or (P(1) and G(0)) or (P(1) and P(0) and cin);
  c(3) <= G(2) or (P(2) and G(1)) or (P(2) and P(1) and G(0)) or (P(2) and P(1) and P(0) and cin);
  cout <= G(3) or (P(3) and G(2)) or (P(3) and P(2) and G(1)) or (P(3) and P(2) and P(1) and G(0))
          or (P(3) and P(2) and P(1) and P(0) and cin);
  blk : for i in 0 to 3 generate
    u : entity work.cla4_block
      port map (a => a(4*i+3 downto 4*i), b => b(4*i+3 downto 4*i), cin => c(i),
                sum => sum(4*i+3 downto 4*i), g_grp => G(i), p_grp => P(i));
  end generate;
end architecture;
