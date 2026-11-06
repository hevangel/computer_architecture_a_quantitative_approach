-- Amdahl's Law:  Speedup_overall = 1 / ((1 - f) + f / s)
--   f : fraction of original execution time that can use the enhancement
--   s : speedup of that fraction when the enhancement is used
-- Fixed point:  f in Q1.16 (65536 = 1.0),  s in Q8.8 (256 = 1.0),
--               result in Q16.16.  s = 0 is invalid and returns 0.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity amdahl_speedup is
  port (
    f_q16       : in  unsigned(16 downto 0);
    s_q8_8      : in  unsigned(15 downto 0);
    speedup_q16 : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of amdahl_speedup is
begin
  process (f_q16, s_q8_8)
    variable serial, enhanced, denom : unsigned(31 downto 0);
    variable numer                   : unsigned(63 downto 0);
    variable f32                     : unsigned(31 downto 0);
  begin
    f32    := resize(f_q16, 32);
    serial := to_unsigned(65536, 32) - f32;                       -- (1 - f)
    if s_q8_8 = 0 then
      enhanced := (others => '0');
    else
      enhanced := shift_left(f32, 8) / resize(s_q8_8, 32);        -- f / s
    end if;
    denom := serial + enhanced;
    numer := shift_left(to_unsigned(1, 64), 32);                  -- 1.0 * 1.0 in Q.32
    if denom = 0 or s_q8_8 = 0 then
      speedup_q16 <= (others => '0');
    else
      speedup_q16 <= resize(numer / resize(denom, 64), 32);
    end if;
  end process;
end architecture;
