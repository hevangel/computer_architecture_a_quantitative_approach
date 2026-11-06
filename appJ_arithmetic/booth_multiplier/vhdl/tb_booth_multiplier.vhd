library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_booth_multiplier is end entity;

architecture sim of tb_booth_multiplier is
  signal clk : std_logic := '0';
  signal rst_n, start : std_logic := '0';
  signal a, b : signed(15 downto 0) := (others => '0');
  signal busy, done : std_logic;
  signal product : signed(31 downto 0);
begin
  clk <= not clk after 5 ns;
  dut : entity work.booth_multiplier port map (clk, rst_n, start, a, b, busy, done, product);

  process
    variable errors, tests : natural := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(777, 32);
    procedure mul(x, y : integer) is
      variable cycles : natural := 0;
    begin
      wait until falling_edge(clk);
      a <= to_signed(x, 16);  b <= to_signed(y, 16);  start <= '1';
      wait until falling_edge(clk);
      start <= '0';
      while done /= '1' and cycles < 20 loop wait until falling_edge(clk); cycles := cycles + 1; end loop;
      tests := tests + 1;
      if done /= '1' or product /= to_signed(x * y, 32) or cycles /= 8 then
        errors := errors + 1;
        report "FAIL " & integer'image(x) & " * " & integer'image(y) & " = " & integer'image(to_integer(product)) severity error;
      end if;
    end procedure;
  begin
    wait until falling_edge(clk); wait until falling_edge(clk);
    rst_n <= '1';
    mul(0, 0);  mul(1, 1);  mul(-1, -1);  mul(32767, 32767);  mul(-32768, -32768);
    mul(-32768, 32767);  mul(-32768, -1);  mul(1234, -5678);  mul(-3, 7);  mul(16#5555#, -16#5556#);
    for i in 1 to 2000 loop
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
      mul(to_integer(signed(seed(31 downto 16))), to_integer(signed(seed(15 downto 0))));
    end loop;
    report integer'image(tests) & " multiplications checked";
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
