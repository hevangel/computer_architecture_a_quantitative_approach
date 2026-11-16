library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_prime_probe_qos is end entity;
architecture test of tb_prime_probe_qos is
    signal clk: std_logic := '0';
    signal reset: std_logic := '1';
    signal partition, valid, domain: std_logic := '0';
    signal addr: unsigned(31 downto 0) := (others=>'0');
    signal ready, response, hit: std_logic;
    signal latency, hits, misses: unsigned(31 downto 0);
begin
    clk <= not clk after 5 ns;
    dut: entity work.prime_probe_qos port map(clk,reset,partition,valid,domain,addr,ready,response,hit,latency,hits,misses);
    process
        procedure begin_scenario(constant use_partition: std_logic) is
        begin reset<='1'; valid<='0'; partition<=use_partition; wait until falling_edge(clk); reset<='0'; end procedure;
        procedure access_line(constant who: std_logic; constant line: natural; constant expected_hit: std_logic) is
            variable elapsed: natural := 0;
        begin
            assert ready='1' report "TEST FAILED: not ready" severity failure;
            valid<='1'; domain<=who; addr<=to_unsigned(line,32); wait until falling_edge(clk); valid<='0';
            while response/='1' and elapsed<10 loop wait until falling_edge(clk); elapsed:=elapsed+1; end loop;
            assert response='1' and hit=expected_hit and to_integer(latency)=elapsed and
                   ((expected_hit='1' and latency=1) or (expected_hit='0' and latency=5))
                report "TEST FAILED: hit or latency" severity failure;
        end procedure;
    begin
        wait until falling_edge(clk);
        begin_scenario('0');
        for i in 0 to 3 loop access_line('1',i,'0'); end loop;
        access_line('1',0,'1');
        assert hits=1 and misses=4 report "TEST FAILED: shared control" severity failure;
        begin_scenario('0');
        for i in 0 to 3 loop access_line('1',i,'0'); end loop;
        access_line('0',100,'0'); access_line('1',0,'0');
        assert hits=0 and misses=5 report "TEST FAILED: shared leak" severity failure;
        begin_scenario('1');
        for i in 0 to 1 loop access_line('1',i,'0'); end loop;
        access_line('1',0,'1');
        assert hits=1 and misses=2 report "TEST FAILED: partition control" severity failure;
        begin_scenario('1');
        for i in 0 to 1 loop access_line('1',i,'0'); end loop;
        for i in 0 to 4 loop access_line('0',100+i,'0'); end loop;
        access_line('1',0,'1'); access_line('1',1,'1');
        assert hits=2 and misses=2 report "TEST FAILED: partition isolation" severity failure;
        report "TEST PASSED"; finish;
    end process;
end architecture;
