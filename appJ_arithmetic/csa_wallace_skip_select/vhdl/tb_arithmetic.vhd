library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_arithmetic is end entity;
architecture test of tb_arithmetic is
    signal a, b: std_logic_vector(15 downto 0) := (others => '0');
    signal cin: std_logic := '0';
    signal skip_sum, select_sum, product: std_logic_vector(15 downto 0);
    signal skip_cout, select_cout: std_logic;
begin
    skip_dut: entity work.carry_skip16 port map(a,b,cin,skip_sum,skip_cout);
    select_dut: entity work.carry_select16 port map(a,b,cin,select_sum,select_cout);
    multiply_dut: entity work.wallace8 port map(a(7 downto 0),b(7 downto 0),product);
    process
        variable state: unsigned(31 downto 0) := x"12345678";
        variable av, bv, cv: integer;
        variable expected: unsigned(16 downto 0);
    begin
        for x in 0 to 255 loop
            for y in 0 to 255 loop
                a <= std_logic_vector(to_unsigned(x,16)); b <= std_logic_vector(to_unsigned(y,16));
                cv := (x+y) mod 2;
                if cv = 1 then cin <= '1'; else cin <= '0'; end if;
                wait for 1 ns;
                expected := to_unsigned(x+y+cv,17);
                assert unsigned(product) = to_unsigned(x*y,16) and
                       unsigned(skip_cout & skip_sum) = expected and unsigned(select_cout & select_sum) = expected
                    report "TEST FAILED: exhaustive multiply/add" severity failure;
            end loop;
        end loop;
        for k in 0 to 9999 loop
            state := resize(state * to_unsigned(1664525,32) + to_unsigned(1013904223,32),32);
            av := to_integer(state(15 downto 0));
            state := resize(state * to_unsigned(1664525,32) + to_unsigned(1013904223,32),32);
            bv := to_integer(state(31 downto 16));
            cv := k mod 2;
            a <= std_logic_vector(to_unsigned(av,16)); b <= std_logic_vector(to_unsigned(bv,16));
            if cv = 1 then cin <= '1'; else cin <= '0'; end if;
            wait for 1 ns;
            expected := to_unsigned(av+bv+cv,17);
            assert unsigned(skip_cout & skip_sum) = expected and unsigned(select_cout & select_sum) = expected
                report "TEST FAILED: random add" severity failure;
        end loop;
        a <= x"ffff"; b <= x"0000"; cin <= '1'; wait for 1 ns;
        assert unsigned(skip_cout & skip_sum) = to_unsigned(65536,17) and
               unsigned(select_cout & select_sum) = to_unsigned(65536,17)
            report "TEST FAILED: full carry chain" severity failure;
        report "TEST PASSED"; finish;
    end process;
end architecture;
