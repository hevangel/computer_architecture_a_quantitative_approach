library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_amdahl_speedup is end entity;

architecture sim of tb_amdahl_speedup is
  signal f : unsigned(16 downto 0) := (others => '0');
  signal s : unsigned(15 downto 0) := (others => '0');
  signal y : unsigned(31 downto 0);
begin
  dut : entity work.amdahl_speedup port map (f_q16 => f, s_q8_8 => s, speedup_q16 => y);

  process
    variable errors : integer := 0;
    procedure check(f_i : integer; s_i : integer; expected : integer; name : string) is
      variable diff : integer;
    begin
      f <= to_unsigned(f_i, 17);
      s <= to_unsigned(s_i, 16);
      wait for 1 ns;
      diff := abs (to_integer(y) - expected);
      if diff > 128 then
        errors := errors + 1;
        report "FAIL " & name & ": got " & integer'image(to_integer(y)) &
               " expected " & integer'image(expected) severity error;
      else
        report "ok   " & name severity note;
      end if;
    end procedure;
  begin
    check(52429, 2560,  234057, "f=0.80 s=10   -> 3.5714");
    check(32768, 512,    87381, "f=0.50 s=2    -> 1.3333");
    check(58982, 25600, 601248, "f=0.90 s=100  -> 9.1743");
    check(0,     2048,   65536, "f=0    s=8    -> 1.0");
    check(65536, 2048,  524288, "f=1    s=8    -> 8.0");
    check(16384, 384,    71494, "f=0.25 s=1.5  -> 1.0909");
    check(62259, 4096,  599186, "f=0.95 s=16   -> 9.1429");
    check(32768, 0,          0, "s=0 invalid  -> 0");
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
