library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_cpi_power_counters is end entity;
architecture test of tb_cpi_power_counters is
    signal clk: std_logic := '0';
    signal reset: std_logic := '1';
    signal kind: unsigned(1 downto 0) := (others=>'0');
    signal data_word: std_logic_vector(31 downto 0) := (others=>'0');
    signal retire_b, stall_b, retire_f, stall_f, gate: std_logic := '0';
    signal cycles_b, retired_b, stalls_b, toggles_b, cycles_f, retired_f, stalls_f, toggles_f: unsigned(31 downto 0);
    signal retired_classes_b, stall_classes_b, retired_classes_f, stall_classes_f: std_logic_vector(127 downto 0);
    signal cpi_b, cpi_f: unsigned(47 downto 0);
    signal dyn_b, stat_b, power_b, dyn_f, stat_f, power_f: unsigned(63 downto 0);
begin
    clk <= not clk after 5 ns;
    baseline: entity work.cpi_power_counters port map(clk,reset,retire_b,kind,stall_b,kind,'1',data_word,
        cycles_b,retired_b,stalls_b,toggles_b,retired_classes_b,stall_classes_b,cpi_b,dyn_b,stat_b,power_b);
    improved: entity work.cpi_power_counters port map(clk,reset,retire_f,kind,stall_f,kind,gate,data_word,
        cycles_f,retired_f,stalls_f,toggles_f,retired_classes_f,stall_classes_f,cpi_f,dyn_f,stat_f,power_f);
    process
    begin
        wait until falling_edge(clk); reset <= '0';
        for i in 0 to 9 loop
            kind <= to_unsigned(i mod 4,2);
            if i mod 2 = 0 then data_word <= x"ffffffff"; else data_word <= x"00000000"; end if;
            if i < 6 then retire_b <= '1'; stall_b <= '0'; else retire_b <= '0'; stall_b <= '1'; end if;
            if i < 8 then retire_f <= '1'; stall_f <= '0'; else retire_f <= '0'; stall_f <= '1'; end if;
            if (i mod 4) < 2 then gate <= '1'; else gate <= '0'; end if;
            wait until falling_edge(clk);
        end loop;
        assert cycles_b=10 and retired_b=6 and stalls_b=4 and cpi_b=109226 and
               cycles_f=10 and retired_f=8 and stalls_f=2 and cpi_f=81920
            report "TEST FAILED: CPI counts" severity failure;
        assert retired_classes_b=x"00000001000000010000000200000002" and
               stall_classes_b=x"00000001000000010000000100000001" and
               retired_classes_f=x"00000002000000020000000200000002" and
               stall_classes_f=x"00000000000000000000000100000001"
            report "TEST FAILED: class counts" severity failure;
        assert toggles_b=320 and toggles_f=192 and dyn_b=20971520 and dyn_f=12582912 and
               stat_b=163840 and stat_f=163840 and power_b=2113536 and power_f=2113536
            report "TEST FAILED: energy counts" severity failure;
        assert dyn_f * 10 <= dyn_b * 7 report "TEST FAILED: dynamic energy reduction" severity failure;
        report "TEST PASSED"; finish;
    end process;
end architecture;
