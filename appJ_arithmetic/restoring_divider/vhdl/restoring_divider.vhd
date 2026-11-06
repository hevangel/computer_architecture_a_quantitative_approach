-- Unsigned 16-bit restoring divider (Appendix J): one quotient bit per clock.
-- Each step shifts the partial remainder left, brings down the next dividend bit and
-- tries to subtract the divisor; if the result would be negative the subtraction is
-- "restored" (not committed) and the quotient bit is 0.
-- Division by zero follows the RISC-V convention: quotient = all ones, remainder = dividend.
-- Latency: 16 cycles after `start`.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity restoring_divider is
  port (
    clk, rst_n : in  std_logic;
    start      : in  std_logic;
    dividend   : in  unsigned(15 downto 0);
    divisor    : in  unsigned(15 downto 0);
    busy, done : out std_logic;
    quotient   : out unsigned(15 downto 0);
    remainder  : out unsigned(15 downto 0)
  );
end entity;

architecture rtl of restoring_divider is
  signal n, d, q : unsigned(15 downto 0) := (others => '0');
  signal r : unsigned(16 downto 0) := (others => '0');
  signal bit_idx : natural range 0 to 16 := 0;
  signal busy_i, done_i : std_logic := '0';
  signal shifted, diff : unsigned(16 downto 0);
begin
  busy <= busy_i;  done <= done_i;  quotient <= q;  remainder <= r(15 downto 0);
  shifted <= r(15 downto 0) & n(15);
  diff    <= shifted - resize(d, 17);

  process (clk, rst_n)
  begin
    if rst_n = '0' then
      busy_i <= '0';  done_i <= '0';  n <= (others => '0');  d <= (others => '0');
      q <= (others => '0');  r <= (others => '0');  bit_idx <= 0;
    elsif rising_edge(clk) then
      if start = '1' and busy_i = '0' then
        n <= dividend;  d <= divisor;  q <= (others => '0');  r <= (others => '0');
        bit_idx <= 0;  busy_i <= '1';  done_i <= '0';
      elsif busy_i = '1' then
        n <= n(14 downto 0) & '0';
        if diff(16) = '0' then
          r <= diff;     q <= q(14 downto 0) & '1';          -- fits: commit
        else
          r <= shifted;  q <= q(14 downto 0) & '0';          -- restore
        end if;
        bit_idx <= bit_idx + 1;
        if bit_idx = 15 then busy_i <= '0'; done_i <= '1'; end if;
      end if;
      if done_i = '1' and start = '1' then done_i <= '0'; end if;
    end if;
  end process;
end architecture;
