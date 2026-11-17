library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpi_power_counters is
    generic(DYNAMIC_ENERGY_PER_TOGGLE_Q16: natural := 65536;
            STATIC_ENERGY_PER_CYCLE_Q16: natural := 16384;
            CLOCK_HZ: natural := 1);
    port(clk, reset, retire: in std_logic; instruction_class: in unsigned(1 downto 0);
         stall: in std_logic; stall_class: in unsigned(1 downto 0);
         activity_enable: in std_logic; activity_data: in std_logic_vector(31 downto 0);
         cycles, retired, stalls, toggles: out unsigned(31 downto 0);
         retired_by_class, stalls_by_class: out std_logic_vector(127 downto 0);
         cpi_q16: out unsigned(47 downto 0);
         dynamic_energy_q16, static_energy_q16, last_power_q16: out unsigned(63 downto 0));
end entity;

architecture rtl of cpi_power_counters is
    signal cycle_r, retired_r, stall_r, toggle_r: unsigned(31 downto 0) := (others => '0');
    signal retired_classes, stall_classes: std_logic_vector(127 downto 0) := (others => '0');
    signal dynamic_r, static_r, power_r: unsigned(63 downto 0) := (others => '0');
    signal last_data: std_logic_vector(31 downto 0) := (others => '0');
begin
    cycles <= cycle_r; retired <= retired_r; stalls <= stall_r; toggles <= toggle_r;
    retired_by_class <= retired_classes; stalls_by_class <= stall_classes;
    dynamic_energy_q16 <= dynamic_r; static_energy_q16 <= static_r; last_power_q16 <= power_r;
    cpi_q16 <= (others => '0') when retired_r = 0 else
               shift_left(resize(cycle_r,48),16) / resize(retired_r,48);
    process(clk)
        variable transitions: natural range 0 to 32;
        variable increment, per_cycle_energy: unsigned(63 downto 0);
        variable idx: natural range 0 to 3;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                cycle_r <= (others=>'0'); retired_r <= (others=>'0');
                stall_r <= (others=>'0'); toggle_r <= (others=>'0');
                retired_classes <= (others=>'0'); stall_classes <= (others=>'0');
                dynamic_r <= (others=>'0'); static_r <= (others=>'0'); power_r <= (others=>'0');
                last_data <= (others=>'0');
            else
                transitions := 0;
                if activity_enable = '1' then
                    for bit_index in 0 to 31 loop
                        if activity_data(bit_index) /= last_data(bit_index) then transitions := transitions + 1; end if;
                    end loop;
                    last_data <= activity_data;
                end if;
                increment := resize(to_unsigned(transitions,6) * to_unsigned(DYNAMIC_ENERGY_PER_TOGGLE_Q16,32),64);
                per_cycle_energy := increment + to_unsigned(STATIC_ENERGY_PER_CYCLE_Q16,64);
                cycle_r <= cycle_r + 1;
                if retire = '1' then
                    retired_r <= retired_r + 1; idx := to_integer(instruction_class);
                    retired_classes(idx*32+31 downto idx*32) <=
                        std_logic_vector(unsigned(retired_classes(idx*32+31 downto idx*32)) + 1);
                end if;
                if stall = '1' then
                    stall_r <= stall_r + 1; idx := to_integer(stall_class);
                    stall_classes(idx*32+31 downto idx*32) <=
                        std_logic_vector(unsigned(stall_classes(idx*32+31 downto idx*32)) + 1);
                end if;
                toggle_r <= toggle_r + to_unsigned(transitions,32);
                dynamic_r <= dynamic_r + increment;
                static_r <= static_r + to_unsigned(STATIC_ENERGY_PER_CYCLE_Q16,64);
                power_r <= resize(per_cycle_energy * to_unsigned(CLOCK_HZ,32),64);
            end if;
        end if;
    end process;
end architecture;
