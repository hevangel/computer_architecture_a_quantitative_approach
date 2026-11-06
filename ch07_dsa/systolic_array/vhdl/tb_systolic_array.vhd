library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_systolic_array is end entity;

architecture sim of tb_systolic_array is
  constant DIM  : positive := 4;
  constant ROWS  : positive := 9;
  constant DW : positive := 8;
  constant AW : positive := 32;

  type w_t is array (0 to DIM-1, 0 to DIM-1) of integer;
  type a_t is array (0 to ROWS-1, 0 to DIM-1) of integer;
  type c_t is array (0 to ROWS-1, 0 to DIM-1) of integer;
  type cyc_t is array (0 to ROWS-1) of natural;

  -- deterministic pseudo-random int8 stream (LCG), element i of the stream
  function rnd8_at(i : natural) return integer is
    variable seed : unsigned(31 downto 0) := to_unsigned(31337, 32);
  begin
    for j in 0 to i loop
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
    end loop;
    return to_integer(signed(seed(23 downto 16)));
  end function;

  function make_w return w_t is
    variable w : w_t;
  begin
    for k in 0 to DIM-1 loop for n in 0 to DIM-1 loop w(k, n) := rnd8_at(k*DIM + n); end loop; end loop;
    w(0, 0) := -128;  w(1, 1) := 127;                    -- extreme values
    return w;
  end function;
  function make_a return a_t is
    variable a : a_t;
  begin
    for m in 0 to ROWS-1 loop for k in 0 to DIM-1 loop a(m, k) := rnd8_at(DIM*DIM + m*DIM + k); end loop; end loop;
    a(0, 0) := -128;  a(1, 1) := 127;
    return a;
  end function;
  function golden(w : w_t; a : a_t) return c_t is      -- plain nested-loop matrix product
    variable c : c_t;
  begin
    for m in 0 to ROWS-1 loop for n in 0 to DIM-1 loop
      c(m, n) := 0;
      for k in 0 to DIM-1 loop c(m, n) := c(m, n) + a(m, k) * w(k, n); end loop;
    end loop; end loop;
    return c;
  end function;

  constant W_c : w_t := make_w;
  constant A_c : a_t := make_a;
  constant C_c : c_t := golden(W_c, A_c);

  signal clk : std_logic := '0';
  signal rst_n, w_we, in_valid : std_logic := '0';
  signal w_row : natural range 0 to DIM-1 := 0;
  signal w_data, a_in : std_logic_vector(DIM*DW-1 downto 0) := (others => '0');
  signal out_valid : std_logic;
  signal c_out : std_logic_vector(DIM*AW-1 downto 0);

  signal cycle      : natural := 0;
  signal sent_cycle : cyc_t := (others => 0);
  signal got, errors : natural := 0;
begin
  clk <= not clk after 5 ns;
  dut : entity work.systolic_array generic map (DIM, DW, AW)
    port map (clk, rst_n, w_we, w_row, w_data, in_valid, a_in, out_valid, c_out);

  process (clk) begin if rising_edge(clk) then cycle <= cycle + 1; end if; end process;

  -- every valid output row must equal the next golden row, exactly 2N-1 cycles after it was sent
  checker : process (clk)
    variable g : natural := 0;
    variable e : natural := 0;
  begin
    if rising_edge(clk) and out_valid = '1' and rst_n = '1' and g < ROWS then
      for n in 0 to DIM-1 loop
        if to_integer(signed(c_out(n*AW + AW-1 downto n*AW))) /= C_c(g, n) then
          e := e + 1;
          report "FAIL C[" & integer'image(g) & "][" & integer'image(n) & "] = " &
                 integer'image(to_integer(signed(c_out(n*AW + AW-1 downto n*AW)))) &
                 ", expected " & integer'image(C_c(g, n)) severity error;
        end if;
      end loop;
      if cycle - sent_cycle(g) /= 2*DIM - 1 then
        e := e + 1;
        report "FAIL latency of row " & integer'image(g) & ": " & integer'image(cycle - sent_cycle(g)) severity error;
      end if;
      g := g + 1;
      got <= g;  errors <= e;
    end if;
  end process;

  stim : process
  begin
    wait until falling_edge(clk); wait until falling_edge(clk); wait until falling_edge(clk);
    rst_n <= '1';
    for k in 0 to DIM-1 loop                                      -- load weights, one row per cycle
      wait until falling_edge(clk);
      w_we <= '1';  w_row <= k;
      for n in 0 to DIM-1 loop w_data(n*DW + DW-1 downto n*DW) <= std_logic_vector(to_signed(W_c(k, n), DW)); end loop;
    end loop;
    wait until falling_edge(clk);  w_we <= '0';

    for m in 0 to ROWS-1 loop                                      -- 5 back-to-back rows, an idle gap, 4 more
      if m = 5 then
        wait until falling_edge(clk);  in_valid <= '0';
        for g in 1 to 3 loop wait until falling_edge(clk); end loop;
      end if;
      wait until falling_edge(clk);
      in_valid <= '1';
      sent_cycle(m) <= cycle;
      for k in 0 to DIM-1 loop a_in(k*DW + DW-1 downto k*DW) <= std_logic_vector(to_signed(A_c(m, k), DW)); end loop;
    end loop;
    wait until falling_edge(clk);  in_valid <= '0';  a_in <= (others => '0');
    for g in 1 to 3*DIM loop wait until falling_edge(clk); end loop;

    if got /= ROWS then
      report "FAIL: received " & integer'image(got) & " of " & integer'image(ROWS) & " result rows" severity error;
      report "TEST FAILED";
    elsif errors /= 0 then
      report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    else
      report "TEST PASSED";
    end if;
    finish;
  end process;
end architecture;
