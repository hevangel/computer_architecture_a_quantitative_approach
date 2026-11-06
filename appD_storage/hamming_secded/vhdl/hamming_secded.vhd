-- SECDED (72,64) extended Hamming code: corrects any single-bit error, detects any double-bit
-- error.  This is the code used on ECC DRAM DIMMs (8 check bits per 64 data bits).
--
-- Codeword layout (index 0 is the LSB):
--   (0)            overall even-parity bit (turns Hamming distance 3 into 4)
--   (1..71)        Hamming positions; check bits sit at the powers of two 1,2,4,...,64
--                  and the 64 data bits fill the remaining positions in ascending order.
-- Check bit 2^k covers every position whose index has bit k set.  On decode the syndrome
-- *is* the index of the flipped bit.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity secded_encoder is
  port (data : in std_logic_vector(63 downto 0); code : out std_logic_vector(71 downto 0));
end entity;

architecture rtl of secded_encoder is
begin
  process (data)
    variable cw : std_logic_vector(71 downto 0);
    variable d  : natural;
    variable p  : std_logic;
  begin
    cw := (others => '0');
    d := 0;
    for i in 1 to 71 loop
      if (to_unsigned(i, 7) and to_unsigned(i - 1, 7)) /= 0 then   -- not a power of two
        cw(i) := data(d);  d := d + 1;
      end if;
    end loop;
    for k in 0 to 6 loop
      p := '0';
      for i in 1 to 71 loop
        if to_unsigned(i, 7)(k) = '1' then p := p xor cw(i); end if;   -- cw(2**k) is still 0 here
      end loop;
      cw(2 ** k) := p;
    end loop;
    p := '0';
    for i in 1 to 71 loop p := p xor cw(i); end loop;
    cw(0) := p;
    code <= cw;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity secded_decoder is
  port (code : in std_logic_vector(71 downto 0);
        data : out std_logic_vector(63 downto 0);
        single_err : out std_logic;       -- a single-bit error was found and corrected
        double_err : out std_logic);      -- uncorrectable (double-bit) error detected
end entity;

architecture rtl of secded_decoder is
begin
  process (code)
    variable syn     : unsigned(6 downto 0);
    variable overall : std_logic;
    variable cw      : std_logic_vector(71 downto 0);
    variable d       : natural;
    variable s, df   : std_logic;
    variable dout    : std_logic_vector(63 downto 0);
  begin
    for k in 0 to 6 loop
      syn(k) := '0';
      for i in 1 to 71 loop
        if to_unsigned(i, 7)(k) = '1' then syn(k) := syn(k) xor code(i); end if;
      end loop;
    end loop;
    overall := '0';
    for i in 0 to 71 loop overall := overall xor code(i); end loop;
    cw := code;  s := '0';  df := '0';
    if overall = '1' then                  -- odd number of errors: assume one
      if syn = 0 then
        s := '1';  cw(0) := not cw(0);     -- the parity bit itself
      elsif to_integer(syn) < 72 then
        s := '1';  cw(to_integer(syn)) := not cw(to_integer(syn));
      else
        df := '1';                         -- impossible syndrome
      end if;
    elsif syn /= 0 then
      df := '1';                           -- even number of errors, nonzero syndrome
    end if;
    dout := (others => '0');
    d := 0;
    for i in 1 to 71 loop
      if (to_unsigned(i, 7) and to_unsigned(i - 1, 7)) /= 0 then dout(d) := cw(i); d := d + 1; end if;
    end loop;
    data <= dout;  single_err <= s;  double_err <= df;
  end process;
end architecture;
