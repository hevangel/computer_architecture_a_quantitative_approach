-- Signed 16x16 -> 32-bit multiplier using radix-4 Booth recoding (Appendix J).
-- Recoding the multiplier two bits at a time halves the number of partial products:
-- each step examines bits (b[2i+1], b[2i], b[2i-1]) and adds one of 0, +-M, +-2M, shifted by 2i.
-- Latency: 8 clock cycles after `start`.  `done` is high while the product is valid.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity booth_multiplier is
  port (
    clk, rst_n : in  std_logic;
    start      : in  std_logic;
    a, b       : in  signed(15 downto 0);
    busy, done : out std_logic;
    product    : out signed(31 downto 0)
  );
end entity;

architecture rtl of booth_multiplier is
  signal m, acc : signed(31 downto 0) := (others => '0');
  signal q      : std_logic_vector(16 downto 0) := (others => '0');
  signal steps  : natural range 0 to 8 := 0;
  signal busy_i, done_i : std_logic := '0';
  signal term   : signed(31 downto 0);
begin
  busy <= busy_i;  done <= done_i;  product <= acc;

  process (all)
  begin
    case q(2 downto 0) is
      when "001" | "010" => term <= m;
      when "011"         => term <= shift_left(m, 1);
      when "100"         => term <= -shift_left(m, 1);
      when "101" | "110" => term <= -m;
      when others        => term <= (others => '0');      -- 000 and 111
    end case;
  end process;

  process (clk, rst_n)
  begin
    if rst_n = '0' then
      busy_i <= '0';  done_i <= '0';  acc <= (others => '0');  m <= (others => '0');
      q <= (others => '0');  steps <= 0;
    elsif rising_edge(clk) then
      if start = '1' and busy_i = '0' then
        m <= resize(a, 32);  q <= std_logic_vector(b) & '0';  acc <= (others => '0');
        steps <= 0;  busy_i <= '1';  done_i <= '0';
      elsif busy_i = '1' then
        acc <= acc + term;
        m <= shift_left(m, 2);
        q <= "00" & q(16 downto 2);
        steps <= steps + 1;
        if steps = 7 then busy_i <= '0'; done_i <= '1'; end if;
      end if;
      if done_i = '1' and start = '1' then done_i <= '0'; end if;
    end if;
  end process;
end architecture;
