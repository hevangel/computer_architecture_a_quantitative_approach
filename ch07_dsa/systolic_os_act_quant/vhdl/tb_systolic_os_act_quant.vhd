library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_systolic_os_act_quant is end entity;
architecture test of tb_systolic_os_act_quant is
    signal clk: std_logic := '0';
    signal reset: std_logic := '1';
    signal start: std_logic := '0';
    signal a,b: std_logic_vector(127 downto 0) := (others=>'0');
    signal bias: std_logic_vector(511 downto 0) := (others=>'0');
    signal activation: unsigned(1 downto 0) := (others=>'0');
    signal shift: unsigned(4 downto 0) := (others=>'0');
    signal busy,done: std_logic;
    signal accumulators: std_logic_vector(511 downto 0);
    signal quantized: std_logic_vector(127 downto 0);
begin
    clk<=not clk after 5 ns;
    dut: entity work.systolic_os_act_quant port map(clk,reset,start,a,b,bias,activation,shift,busy,done,accumulators,quantized);
    process
        type numbers is array(0 to 15) of integer;
        file vectors: text;
        variable status: file_open_status;
        variable row: line;
        variable mode,sh,av,bv,bias_v,acc_v,q_v: integer;
        variable expected_acc,expected_q: numbers;
    begin
        file_open(status,vectors,"../../../../ch07_dsa/systolic_os_act_quant/golden.txt",read_mode);
        assert status=open_ok report "TEST FAILED: missing vectors" severity failure;
        wait until falling_edge(clk); reset<='0';
        for case_id in 0 to 2 loop
            readline(vectors,row); read(row,mode); read(row,sh); activation<=to_unsigned(mode,2); shift<=to_unsigned(sh,5);
            for i in 0 to 15 loop
                readline(vectors,row); read(row,av); read(row,bv); read(row,bias_v); read(row,acc_v); read(row,q_v);
                a(i*8+7 downto i*8)<=std_logic_vector(to_signed(av,8)); b(i*8+7 downto i*8)<=std_logic_vector(to_signed(bv,8));
                bias(i*32+31 downto i*32)<=std_logic_vector(to_signed(bias_v,32));
                expected_acc(i):=acc_v; expected_q(i):=q_v;
            end loop;
            start<='1'; wait until falling_edge(clk); start<='0';
            assert busy='1' and done='0' report "TEST FAILED: start" severity failure;
            a<=(others=>'0'); b<=(others=>'0'); bias<=(others=>'0'); activation<=(others=>'0'); shift<=(others=>'0');
            for cycle in 0 to 9 loop
                wait until falling_edge(clk);
                if cycle<9 then assert busy='1' and done='0' report "TEST FAILED: early completion" severity failure; end if;
            end loop;
            assert busy='0' and done='1' report "TEST FAILED: completion latency" severity failure;
            for i in 0 to 15 loop
                assert signed(accumulators(i*32+31 downto i*32))=to_signed(expected_acc(i),32) and
                       signed(quantized(i*8+7 downto i*8))=to_signed(expected_q(i),8)
                    report "TEST FAILED: output lane" severity failure;
            end loop;
        end loop;
        file_close(vectors); report "TEST PASSED"; finish;
    end process;
end architecture;
