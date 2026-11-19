library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_consistency_litmus_tsosb is end entity;
architecture test of tb_consistency_litmus_tsosb is
    signal clk: std_logic := '0';
    signal reset: std_logic := '1';
    signal tso, valid, core, address: std_logic := '0';
    signal op: unsigned(1 downto 0) := (others=>'0');
    signal data: unsigned(31 downto 0) := (others=>'0');
    signal accepted, read_valid: std_logic;
    signal read_data, x, y: unsigned(31 downto 0);
    signal pending0, pending1: unsigned(1 downto 0);
begin
    clk<=not clk after 5 ns;
    dut: entity work.consistency_litmus_tsosb port map(clk,reset,tso,valid,core,op,address,data,accepted,read_valid,read_data,x,y,pending0,pending1);
    process
        procedure init(constant mode: std_logic) is
        begin reset<='1'; tso<=mode; valid<='0'; wait until falling_edge(clk); reset<='0'; end procedure;
        procedure command(constant who: std_logic; constant opcode: natural; constant addr: std_logic;
                          constant value: natural; variable read_result: out integer) is
            variable attempts: natural;
        begin
            core<=who; op<=to_unsigned(opcode,2); address<=addr; data<=to_unsigned(value,32); valid<='1'; attempts:=0;
            wait until falling_edge(clk); attempts:=attempts+1;
            while accepted/='1' and attempts<5 loop wait until falling_edge(clk); attempts:=attempts+1; end loop;
            assert accepted='1' report "TEST FAILED: stalled command" severity failure;
            assert opcode/=1 or read_valid='1' report "TEST FAILED: load response" severity failure;
            read_result:=to_integer(read_data); valid<='0';
        end procedure;
        variable steps, bit_count, c, pos0, pos1, r0, r1, cases, result: integer;
    begin
        wait until falling_edge(clk); cases:=0;
        for mode in 0 to 1 loop
            for fenced in 0 to 1 loop
                if fenced=1 then steps:=3; else steps:=2; end if;
                for mask in 0 to (2**(steps*2))-1 loop
                    bit_count:=0;
                    for j in 0 to steps*2-1 loop bit_count:=bit_count+((mask/(2**j)) mod 2); end loop;
                    if bit_count=steps then
                        if mode=1 then init('1'); else init('0'); end if;
                        pos0:=0; pos1:=0; r0:=-1; r1:=-1;
                        for j in 0 to steps*2-1 loop
                            c:=(mask/(2**j)) mod 2;
                            if c=0 then
                                if pos0=0 then command('0',0,'0',1,result);
                                elsif fenced=1 and pos0=1 then command('0',3,'0',0,result);
                                else command('0',1,'1',0,result); r0:=result; end if;
                                pos0:=pos0+1;
                            else
                                if pos1=0 then command('1',0,'1',1,result);
                                elsif fenced=1 and pos1=1 then command('1',3,'0',0,result);
                                else command('1',1,'0',0,result); r1:=result; end if;
                                pos1:=pos1+1;
                            end if;
                        end loop;
                        assert r0>=0 and r1>=0 report "TEST FAILED: missing read" severity failure;
                        assert not ((mode=0 or fenced=1) and r0=0 and r1=0)
                            report "TEST FAILED: forbidden SB outcome" severity failure;
                        assert not (mode=1 and fenced=0 and (r0/=0 or r1/=0))
                            report "TEST FAILED: TSO buffered SB" severity failure;
                        cases:=cases+1;
                    end if;
                end loop;
            end loop;
        end loop;
        assert cases=52 report "TEST FAILED: schedule count" severity failure;
        init('1'); command('0',0,'0',11,result); command('0',0,'0',22,result);
        command('0',1,'0',0,result); assert result=22 and x=0 report "TEST FAILED: forwarding" severity failure;
        core<='0'; op<="00"; address<='1'; data<=to_unsigned(33,32); valid<='1'; wait until falling_edge(clk); valid<='0';
        assert accepted='0' and pending0=2 report "TEST FAILED: full buffer" severity failure;
        command('0',2,'0',0,result); assert x=11 and pending0=1 report "TEST FAILED: first drain" severity failure;
        command('0',2,'0',0,result); assert x=22 and pending0=0 report "TEST FAILED: second drain" severity failure;
        init('1'); command('0',0,'0',42,result); command('0',0,'1',1,result);
        command('0',2,'0',0,result); command('1',1,'1',0,result); assert result=0 report "TEST FAILED: early flag" severity failure;
        command('0',2,'0',0,result); command('1',1,'1',0,result); assert result=1 report "TEST FAILED: flag" severity failure;
        command('1',1,'0',0,result); assert result=42 report "TEST FAILED: data after flag" severity failure;
        report "TEST PASSED"; finish;
    end process;
end architecture;
