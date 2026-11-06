-- DAXPY (Y = a*X + Y) on a 4-lane and a 1-lane vector unit.  Results must be identical and each
-- vector instruction must take exactly ceil(vl/L) cycles.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_vector_unit is end entity;

architecture sim of tb_vector_unit is
  constant MVL : positive := 16;
  constant VREGS : positive := 8;
  signal clk : std_logic := '0';
  signal rst_n, ld_we, start : std_logic := '0';
  signal ld_reg, rd_reg, vd, vs1, vs2 : natural range 0 to VREGS-1 := 0;
  signal ld_idx, rd_idx : natural range 0 to MVL-1 := 0;
  signal ld_data, scalar : signed(31 downto 0) := (others => '0');
  signal op : natural range 0 to 7 := 0;
  signal vl : natural range 0 to MVL := 0;
  signal rd4, rd1 : signed(31 downto 0);
  signal busy4, busy1 : std_logic;
  signal cnt4, cnt1 : natural := 0;
begin
  clk <= not clk after 5 ns;
  u4 : entity work.vector_unit generic map (4, MVL, VREGS)
    port map (clk, rst_n, ld_we, ld_reg, ld_idx, ld_data, rd_reg, rd_idx, rd4, start, op, vd, vs1, vs2, scalar, vl, busy4);
  u1 : entity work.vector_unit generic map (1, MVL, VREGS)
    port map (clk, rst_n, ld_we, ld_reg, ld_idx, ld_data, rd_reg, rd_idx, rd1, start, op, vd, vs1, vs2, scalar, vl, busy1);

  process (clk) begin
    if rising_edge(clk) then
      if start = '1' then cnt4 <= 0; cnt1 <= 0;
      else
        if busy4 = '1' then cnt4 <= cnt4 + 1; end if;
        if busy1 = '1' then cnt1 <= cnt1 + 1; end if;
      end if;
    end if;
  end process;

  process
    variable errors : natural := 0;
    variable a_scalar : integer := 5;
    variable expected, cyc4_total, cyc1_total : integer;
    type int_vec is array (natural range <>) of integer;
    constant vls : int_vec(0 to 3) := (16, 13, 4, 1);
    variable n : integer;

    procedure vload(r : natural; i : natural; v : integer) is
    begin
      wait until falling_edge(clk);
      ld_we <= '1';  ld_reg <= r;  ld_idx <= i;  ld_data <= to_signed(v, 32);
      wait until falling_edge(clk);
      ld_we <= '0';
    end procedure;

    procedure vexec(o, d, s1, s2 : natural; sc : integer; nn : natural) is
    begin
      wait until falling_edge(clk);
      start <= '1';  op <= o;  vd <= d;  vs1 <= s1;  vs2 <= s2;  scalar <= to_signed(sc, 32);  vl <= nn;
      wait until falling_edge(clk);
      start <= '0';
      while busy4 = '1' or busy1 = '1' loop wait until falling_edge(clk); end loop;
      wait until falling_edge(clk);
    end procedure;

    procedure check_elem(r : natural; i : natural; expect : integer; what : string) is
    begin
      rd_reg <= r;  rd_idx <= i;
      wait for 1 ns;
      if to_integer(rd4) /= expect or to_integer(rd1) /= expect then
        errors := errors + 1;
        report "FAIL " & what & " element " & integer'image(i) & ": L4=" & integer'image(to_integer(rd4)) &
               " L1=" & integer'image(to_integer(rd1)) & " expected " & integer'image(expect) severity error;
      end if;
    end procedure;

    procedure check_cycles(what : string; nn : natural) is
    begin
      if cnt4 /= (nn + 3) / 4 or cnt1 /= nn then
        errors := errors + 1;
        report "FAIL cycles for " & what & " vl=" & integer'image(nn) & ": L4=" & integer'image(cnt4) & " L1=" & integer'image(cnt1) severity error;
      end if;
    end procedure;
  begin
    wait until falling_edge(clk);  wait until falling_edge(clk);
    rst_n <= '1';

    for t in vls'range loop
      n := vls(t);
      for i in 0 to MVL-1 loop vload(1, i, i*3 - 7);  vload(2, i, 100 - 2*i); end loop;      -- V1 = X, V2 = Y
      vexec(3, 3, 1, 0, a_scalar, n);                                    -- V3 = a * X
      check_cycles("VMULS", n);
      cyc4_total := cnt4;  cyc1_total := cnt1;
      vexec(0, 2, 3, 2, 0, n);                                           -- V2 = V3 + V2   (DAXPY done)
      check_cycles("VADD", n);
      cyc4_total := cyc4_total + cnt4;  cyc1_total := cyc1_total + cnt1;
      for i in 0 to MVL-1 loop
        if i < n then expected := a_scalar * (i*3 - 7) + (100 - 2*i); else expected := 100 - 2*i; end if;   -- masked elements untouched
        check_elem(2, i, expected, "DAXPY vl=" & integer'image(n));
      end loop;
      report "DAXPY vl=" & integer'image(n) & ": 4 lanes = " & integer'image(cyc4_total) & " cycles, 1 lane = " & integer'image(cyc1_total) & " cycles";
    end loop;

    -- other opcodes, spot-checked
    for i in 0 to MVL-1 loop vload(4, i, i + 1);  vload(5, i, 10 * (i + 1)); end loop;
    vexec(1, 6, 5, 4, 0, 16);       -- V6 = V5 - V4 = 9*(i+1)
    vexec(2, 7, 4, 5, 0, 16);       -- V7 = V4 * V5 = 10*(i+1)^2
    vexec(4, 4, 4, 0, -100, 16);    -- V4 = V4 + (-100)
    for i in 0 to MVL-1 loop
      check_elem(6, i, 9*(i+1), "VSUB");
      check_elem(7, i, 10*(i+1)*(i+1), "VMUL");
      check_elem(4, i, i + 1 - 100, "VADDS");
    end loop;
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
