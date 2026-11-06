library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_rr_crossbar is end entity;

architecture sim of tb_rr_crossbar is
  constant N : positive := 4;
  constant W : positive := 32;
  constant DW : positive := 2;
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal in_req : std_logic_vector(N-1 downto 0) := (others => '0');
  signal in_dst : std_logic_vector(N*DW-1 downto 0) := (others => '0');
  signal in_data : std_logic_vector(N*W-1 downto 0) := (others => '0');
  signal in_gnt, out_valid : std_logic_vector(N-1 downto 0);
  signal out_src : std_logic_vector(N*DW-1 downto 0);
  signal out_data : std_logic_vector(N*W-1 downto 0);
begin
  clk <= not clk after 5 ns;
  dut : entity work.rr_crossbar generic map (N, W, DW)
    port map (clk, rst_n, in_req, in_dst, in_data, in_gnt, out_valid, out_src, out_data);

  process
    variable errors : natural := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(808, 32);
    variable r : unsigned(31 downto 0);
    variable serial : natural := 0;

    function dst_vec(d0, d1, d2, d3 : natural) return std_logic_vector is
    begin
      return std_logic_vector(to_unsigned(d3, DW) & to_unsigned(d2, DW) & to_unsigned(d1, DW) & to_unsigned(d0, DW));
    end function;

    procedure drive(req : std_logic_vector(N-1 downto 0); dsts : std_logic_vector(N*DW-1 downto 0)) is
    begin
      wait until falling_edge(clk);
      in_req <= req;  in_dst <= dsts;
      for p in 0 to N-1 loop
        serial := serial + 1;
        in_data(p*W + W-1 downto p*W) <= std_logic_vector(unsigned'(x"D0000000") + to_unsigned(p * 256 + serial mod 256, 32));
      end loop;
      wait for 1 ns;
    end procedure;

    impure function src_of(j : natural) return natural is
    begin return to_integer(unsigned(out_src(j*DW + DW-1 downto j*DW))); end function;
    impure function dst_of(i : natural) return natural is
    begin return to_integer(unsigned(in_dst(i*DW + DW-1 downto i*DW))); end function;
    function popcount(v : std_logic_vector) return natural is
      variable cnt : natural := 0;
    begin
      for q in v'range loop if v(q) = '1' then cnt := cnt + 1; end if; end loop;
      return cnt;
    end function;

    variable expv : boolean;
    variable ngnt, sw : natural;
    variable expected_src : natural;
  begin
    wait until falling_edge(clk);  wait until falling_edge(clk);
    rst_n <= '1';

    -- 1. hot spot: everyone wants output 2 -> winners must rotate 0,1,2,3,0,1,2,3
    for c in 0 to 7 loop
      drive("1111", dst_vec(2, 2, 2, 2));
      if out_valid /= "0100" or src_of(2) /= c mod 4 then
        errors := errors + 1;  report "FAIL hotspot cycle " & integer'image(c) severity error;
      end if;
      if in_gnt /= std_logic_vector(shift_left(to_unsigned(1, N), c mod 4)) then
        errors := errors + 1;  report "FAIL hotspot grant vector, cycle " & integer'image(c) severity error;
      end if;
      if out_data(2*W + W-1 downto 2*W) /= in_data((c mod 4)*W + W-1 downto (c mod 4)*W) then
        errors := errors + 1;  report "FAIL hotspot data" severity error;
      end if;
    end loop;

    -- 2. input 1 idle, the rest hot-spot output 0 -> rotate 0,2,3,0,2,3 (idle input is skipped)
    for c in 0 to 5 loop
      drive("1101", dst_vec(0, 0, 0, 0));
      if c mod 3 = 0 then expected_src := 0; elsif c mod 3 = 1 then expected_src := 2; else expected_src := 3; end if;
      if src_of(0) /= expected_src then
        errors := errors + 1;  report "FAIL skip-idle cycle " & integer'image(c) severity error;
      end if;
    end loop;

    -- 3. permutation traffic i -> i+1: no conflicts, all four served every cycle
    for c in 0 to 3 loop
      drive("1111", dst_vec(1, 2, 3, 0));
      if in_gnt /= "1111" or out_valid /= "1111" then errors := errors + 1;  report "FAIL permutation grants" severity error; end if;
      for j in 0 to N-1 loop
        if src_of(j) /= (j + N - 1) mod N or
           out_data(j*W + W-1 downto j*W) /= in_data(((j + N - 1) mod N)*W + W-1 downto ((j + N - 1) mod N)*W) then
          errors := errors + 1;  report "FAIL permutation routing at output " & integer'image(j) severity error;
        end if;
      end loop;
    end loop;

    -- 4. random traffic: check arbiter invariants every cycle
    for c in 0 to 2999 loop
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
      r := seed;
      drive(std_logic_vector(r(3 downto 0)),
            dst_vec(to_integer(r(5 downto 4)), to_integer(r(7 downto 6)), to_integer(r(9 downto 8)), to_integer(r(11 downto 10))));
      ngnt := 0;
      for j in 0 to N-1 loop
        expv := false;
        for i in 0 to N-1 loop
          if in_req(i) = '1' and dst_of(i) = j then expv := true; end if;
        end loop;
        if (out_valid(j) = '1') /= expv then errors := errors + 1;  report "FAIL output valid mismatch" severity error; end if;
        if out_valid(j) = '1' then
          sw := src_of(j);
          if in_req(sw) = '0' or dst_of(sw) /= j or in_gnt(sw) = '0' then
            errors := errors + 1;  report "FAIL bad winner for output " & integer'image(j) severity error;
          end if;
          ngnt := ngnt + 1;
        end if;
      end loop;
      if popcount(in_gnt) /= ngnt then errors := errors + 1;  report "FAIL grant count" severity error; end if;
    end loop;
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
