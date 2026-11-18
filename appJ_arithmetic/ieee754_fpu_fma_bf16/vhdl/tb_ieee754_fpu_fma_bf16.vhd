library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

entity tb_ieee754_fpu_fma_bf16 is end;
architecture test of tb_ieee754_fpu_fma_bf16 is
    signal op, fmt, rounding : unsigned(1 downto 0);
    signal a, b, c, result : unsigned(31 downto 0);
    signal scale_a, scale_b : signed(7 downto 0);
    signal flags : unsigned(4 downto 0);
begin
    dut: entity work.ieee754_fpu_fma_bf16
        port map (op, fmt, rounding, a, b, c, scale_a, scale_b, result, flags);
    process
        file vectors : text open read_mode is "../../../../appJ_arithmetic/ieee754_fpu_fma_bf16/python/fp_vectors.txt";
        variable row : line;
        variable op_v, fmt_v, mode_v, sa, sb : integer;
        variable av, bv, cv, expected : std_logic_vector(31 downto 0);
        variable expected_flags : std_logic_vector(7 downto 0);
        variable n : natural := 0;
    begin
        while not endfile(vectors) loop
            readline(vectors, row);
            read(row, op_v); read(row, fmt_v); read(row, mode_v);
            hread(row, av); hread(row, bv); hread(row, cv);
            read(row, sa); read(row, sb);
            hread(row, expected); hread(row, expected_flags);
            op <= to_unsigned(op_v, 2); fmt <= to_unsigned(fmt_v, 2);
            rounding <= to_unsigned(mode_v, 2);
            a <= unsigned(av); b <= unsigned(bv); c <= unsigned(cv);
            scale_a <= to_signed(sa, 8); scale_b <= to_signed(sb, 8);
            wait for 1 ns;
            assert result = unsigned(expected) and flags = unsigned(expected_flags(4 downto 0))
                report "vector " & integer'image(n) & " expected " & to_hstring(expected) &
                       "/" & to_hstring(expected_flags) & " got " & to_hstring(result) &
                       "/" & to_hstring(flags) severity failure;
            n := n+1;
        end loop;
        assert n >= 5000 report "too few vectors" severity failure;
        report "TEST PASSED (" & integer'image(n) & " vectors)";
        finish;
    end process;
end architecture;
