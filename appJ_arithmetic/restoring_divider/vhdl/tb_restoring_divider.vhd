library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_restoring_divider is end entity;

architecture sim of tb_restoring_divider is
  signal clk : std_logic := '0';
  signal rst_n, start : std_logic := '0';
  signal n, d, q, r : unsigned(15 downto 0) := (others => '0');
  signal busy, done : std_logic;
begin
  clk <= not clk after 5 ns;
  dut : entity work.restoring_divider port map (clk, rst_n, start, n, d, busy, done, q, r);

  process
    variable errors, tests : natural := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(4242, 32);
    procedure div(x, y : natural) is
      variable cycles : natural := 0;
      variable eq, er : natural;
    begin
      if y = 0 then eq := 65535; er := x; else eq := x / y; er := x mod y; end if;
      wait until falling_edge(clk);
      n <= to_unsigned(x, 16);  d <= to_unsigned(y, 16);  start <= '1';
      wait until falling_edge(clk);
      start <= '0';
      while done /= '1' and cycles < 30 loop wait until falling_edge(clk); cycles := cycles + 1; end loop;
      tests := tests + 1;
      if done /= '1' or to_integer(q) /= eq or to_integer(r) /= er or cycles /= 16 then
        errors := errors + 1;
        report "FAIL " & integer'image(x) & " / " & integer'image(y) & " = " & integer'image(to_integer(q)) &
               " r " & integer'image(to_integer(r)) severity error;
      end if;
    end procedure;
  begin
    wait until falling_edge(clk); wait until falling_edge(clk);
    rst_n <= '1';
    div(0, 1);  div(1, 1);  div(100, 7);  div(65535, 1);  div(65535, 65535);  div(5, 9);
    div(32768, 3);  div(1234, 0);  div(0, 0);  div(65535, 2);
    for i in 0 to 1999 loop
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
      if i mod 4 = 0 then div(to_integer(seed(31 downto 16)), to_integer(seed(7 downto 0)));
      else div(to_integer(seed(31 downto 16)), to_integer(seed(15 downto 0)));
      end if;
    end loop;
    report integer'image(tests) & " divisions checked";
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
