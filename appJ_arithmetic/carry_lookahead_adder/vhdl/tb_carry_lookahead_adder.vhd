library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_carry_lookahead_adder is end entity;

architecture sim of tb_carry_lookahead_adder is
  signal a, b, sum : std_logic_vector(15 downto 0) := (others => '0');
  signal cin, cout : std_logic := '0';
begin
  dut : entity work.carry_lookahead_adder port map (a, b, cin, sum, cout);

  process
    variable errors, tests : natural := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(12345, 32);
    procedure check(ai, bi : std_logic_vector(15 downto 0); ci : std_logic) is
      variable expected : unsigned(16 downto 0);
    begin
      a <= ai;  b <= bi;  cin <= ci;
      wait for 1 ns;
      expected := ('0' & unsigned(ai)) + ('0' & unsigned(bi));
      if ci = '1' then expected := expected + 1; end if;
      tests := tests + 1;
      if (cout & sum) /= std_logic_vector(expected) then
        errors := errors + 1;
        report "FAIL addition mismatch" severity error;
      end if;
    end procedure;
  begin
    check(x"0000", x"0000", '0');  check(x"FFFF", x"0000", '1');  check(x"FFFF", x"FFFF", '1');
    check(x"8000", x"8000", '0');  check(x"0001", x"FFFF", '0');  check(x"5555", x"AAAA", '1');
    check(x"000F", x"0001", '0');
    for i in 1 to 20000 loop
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);  -- same LCG as SV
      check(std_logic_vector(seed(31 downto 16)), std_logic_vector(seed(15 downto 0)), seed(7));
    end loop;
    report integer'image(tests) & " additions checked";
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
