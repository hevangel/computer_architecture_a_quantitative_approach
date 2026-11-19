library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_split_bus_transient_msi is end entity;
architecture test of tb_split_bus_transient_msi is
    signal clk : std_logic := '0';
    signal reset, allow_data : std_logic := '1';
    signal req_valid : std_logic_vector(1 downto 0) := "00";
    signal req_op : std_logic_vector(3 downto 0) := x"0";
    signal req_data : std_logic_vector(63 downto 0) := (others=>'0');
    signal req_ready, rsp_valid : std_logic_vector(1 downto 0);
    signal rsp_data : std_logic_vector(63 downto 0);
    signal cache_state : std_logic_vector(7 downto 0);
    signal memory_word, upgrade_races : unsigned(31 downto 0);
begin
    clk <= not clk after 5 ns;
    dut: entity work.split_bus_transient_msi
        port map(clk,reset,allow_data,req_valid,req_op,req_data,req_ready,rsp_valid,rsp_data,cache_state,memory_word,upgrade_races);
    process
        procedure tick is
        begin
            wait until rising_edge(clk); wait for 1 ns;
            assert cache_state/=x"22" report "two modified copies" severity failure;
        end;
        procedure wait_response(core : natural; expected : natural; check_data : boolean := true) is
            variable waited : natural := 0;
        begin
            while rsp_valid(core)/='1' and waited<24 loop tick; waited := waited+1; end loop;
            assert rsp_valid(core)='1' and
                (not check_data or unsigned(rsp_data(32*core+31 downto 32*core))=expected)
                report "response mismatch core " & integer'image(core) severity failure;
        end;
    begin
        tick; reset<='0';
        req_valid<="01"; tick; req_valid<="00"; wait_response(0,0);
        req_valid<="10"; tick; req_valid<="00"; wait_response(1,0);
        assert cache_state=x"11" report "failed to share" severity failure;

        req_valid<="11"; req_op<=x"5"; req_data<=x"0000000900000007"; allow_data<='0'; tick;
        req_valid<="00";
        assert cache_state=x"55" report "two SM_AD requests required" severity failure;
        tick;
        assert cache_state=x"34" and upgrade_races=1 report "loser must fall back to IM_AD" severity failure;
        for step in 1 to 5 loop
            tick;
            assert rsp_valid="00" and cache_state=x"34" report "response did not wait" severity failure;
        end loop;
        allow_data<='1'; wait_response(0,7);
        assert cache_state=x"32" report "first writer missing" severity failure;
        wait_response(1,9);
        assert cache_state=x"20" and memory_word=7 report "ordered retry or writeback failed" severity failure;

        req_op<=x"0"; req_valid<="01"; tick; req_valid<="00"; wait_response(0,9);
        assert cache_state=x"11" and memory_word=9 report "stale read" severity failure;
        req_op<=x"1"; req_data<=x"000000000000000e"; req_valid<="01"; tick; req_valid<="00"; wait_response(0,14);
        req_op<=x"2"; req_valid<="01"; tick; req_valid<="00";
        assert cache_state=x"06" report "missing MI_A on eviction" severity failure;
        wait_response(0,0,false);
        assert cache_state=x"00" and memory_word=14 report "dirty eviction failed" severity failure;
        report "TEST PASSED";
        finish;
    end process;
    process begin wait for 2000 ns; assert false report "timeout" severity failure; end process;
end architecture;
