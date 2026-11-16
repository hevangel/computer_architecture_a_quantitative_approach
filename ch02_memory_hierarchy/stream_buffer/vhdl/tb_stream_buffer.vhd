library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_stream_buffer is end entity;
architecture test of tb_stream_buffer is
    signal clk: std_logic := '0';
    signal reset: std_logic := '1';
    signal valid: std_logic := '0';
    signal address: unsigned(31 downto 0) := (others=>'0');
    signal rb,rp: std_logic;
    signal db,dp: std_logic_vector(31 downto 0);
    signal cb,hb,mb,demand_b,phb,prb,cp,hp,mp,demand_p,php,prp: unsigned(31 downto 0);
begin
    clk <= not clk after 5 ns;
    baseline: entity work.stream_buffer port map(clk,reset,valid,'0',address,rb,db,cb,hb,mb,demand_b,phb,prb);
    prefetched: entity work.stream_buffer port map(clk,reset,valid,'1',address,rp,dp,cp,hp,mp,demand_p,php,prp);
    process
        procedure run_access(constant addr: natural) is
        begin
            address <= to_unsigned(addr,32); valid <= '1'; wait until falling_edge(clk);
            assert rb='1' and rp='1' and unsigned(db)=(to_unsigned(addr,32) xor unsigned'(x"a5c39e71")) and dp=db
                report "TEST FAILED: read data" severity failure;
        end procedure;
        variable test_address: natural;
    begin
        wait until falling_edge(clk); reset <= '0';
        for i in 0 to 31 loop run_access(i); end loop;
        assert cb=32 and cp=32 and mb=32 and mp=32 and demand_b=32 and demand_p=1 and php=31 and prp=35 and
               demand_p*10 <= demand_b*3 report "TEST FAILED: sequential demand reads" severity failure;
        run_access(31);
        assert hb=1 and hp=1 and demand_p=1 and php=31 report "TEST FAILED: L1 hit" severity failure;
        valid <= '0'; reset <= '1'; wait until falling_edge(clk); reset <= '0';
        for i in 0 to 31 loop
            if i mod 2=0 then test_address := i/2; else test_address := 16+i/2; end if;
            run_access(test_address);
        end loop;
        assert cb=32 and cp=32 and demand_b=32 and demand_p=32 and php=0 and prp=128
            report "TEST FAILED: interleaved streams" severity failure;
        report "TEST PASSED"; finish;
    end process;
end architecture;
