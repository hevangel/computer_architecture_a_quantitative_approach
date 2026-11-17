library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tournament_btb_ras is end entity;
architecture test of tb_tournament_btb_ras is
    signal clk: std_logic := '0';
    signal reset: std_logic := '1';
    signal update, taken: std_logic := '0';
    signal kind: unsigned(1 downto 0) := (others=>'0');
    signal pc, target: unsigned(31 downto 0) := (others=>'0');
    signal local_p, global_p, tournament_p, btb_hit, ras_valid: std_logic;
    signal btb_target, ras_target: unsigned(31 downto 0);
begin
    clk <= not clk after 5 ns;
    dut: entity work.tournament_btb_ras port map(clk,reset,pc,update,kind,taken,target,local_p,global_p,tournament_p,
                                                 btb_hit,btb_target,ras_valid,ras_target);
    process
        procedure clear_state is
        begin reset<='1'; update<='0'; wait until falling_edge(clk); reset<='0'; end procedure;
        procedure control(constant op: natural; constant address, destination: natural) is
        begin
            pc<=to_unsigned(address,32); kind<=to_unsigned(op,2); target<=to_unsigned(destination,32); update<='1';
            wait until falling_edge(clk); update<='0'; wait for 1 ns;
        end procedure;
        variable idx, phase, local_correct, global_correct, tournament_correct: integer;
        variable random_state: unsigned(31 downto 0) := x"12345678";
        variable actual: std_logic := '0';
    begin
        wait until falling_edge(clk); clear_state;
        local_correct:=0; global_correct:=0; tournament_correct:=0; kind<="00"; update<='1';
        for k in 0 to 2047 loop
            idx:=k mod 4; phase:=(k/4) mod 4; pc<=to_unsigned(idx*4,32);
            if (idx mod 2=0 and (phase=0 or phase=1)) or (idx mod 2=1 and (phase=0 or phase=3)) then
                actual:='1'; else actual:='0'; end if;
            taken<=actual; wait for 1 ns;
            if k>=128 then
                if local_p=actual then local_correct:=local_correct+1; end if;
                if global_p=actual then global_correct:=global_correct+1; end if;
                if tournament_p=actual then tournament_correct:=tournament_correct+1; end if;
            end if;
            wait until falling_edge(clk);
        end loop;
        update<='0';
        assert local_correct=1920 and global_correct=1440 and tournament_correct=1920
            report "TEST FAILED: periodic trace" severity failure;
        clear_state;
        local_correct:=0; global_correct:=0; tournament_correct:=0; random_state:=x"12345678"; kind<="00"; update<='1';
        for k in 0 to 4095 loop
            pc<=to_unsigned((k mod 2)*4,32);
            if k mod 2=0 then
                random_state:=resize(random_state * to_unsigned(1664525,32) + to_unsigned(1013904223,32),32);
                actual:=random_state(31);
            end if;
            taken<=actual; wait for 1 ns;
            if k>=256 then
                if local_p=actual then local_correct:=local_correct+1; end if;
                if global_p=actual then global_correct:=global_correct+1; end if;
                if tournament_p=actual then tournament_correct:=tournament_correct+1; end if;
            end if;
            wait until falling_edge(clk);
        end loop;
        update<='0';
        assert local_correct=1994 and global_correct=2724 and tournament_correct=2736
            report "TEST FAILED: correlated trace" severity failure;
        clear_state;
        for k in 0 to 3 loop control(1,16#1000#+k*4,16#2000#+k*4); end loop;
        pc<=x"0000100c"; wait for 1 ns;
        assert btb_hit='1' and btb_target=x"0000200c" report "TEST FAILED: BTB hit" severity failure;
        pc<=x"0000101c"; wait for 1 ns;
        assert btb_hit='0' report "TEST FAILED: BTB tag collision" severity failure;
        taken<='1'; control(0,16#101c#,16#3030#);
        assert btb_hit='1' and btb_target=x"00003030" report "TEST FAILED: BTB replacement" severity failure;
        pc<=x"0000100c"; wait for 1 ns;
        assert btb_hit='0' report "TEST FAILED: old BTB entry" severity failure;
        for k in 3 downto 0 loop
            assert ras_valid='1' and ras_target=to_unsigned(16#1000#+k*4+4,32) report "TEST FAILED: return stack" severity failure;
            control(2,0,0);
        end loop;
        assert ras_valid='0' report "TEST FAILED: return stack empty" severity failure;
        control(2,0,0);
        assert ras_valid='0' report "TEST FAILED: return stack underflow" severity failure;
        for k in 0 to 4 loop control(1,16#3000#+k*4,0); end loop;
        for k in 4 downto 1 loop
            assert ras_valid='1' and ras_target=to_unsigned(16#3000#+k*4+4,32) report "TEST FAILED: overflow policy" severity failure;
            control(2,0,0);
        end loop;
        assert ras_valid='0' report "TEST FAILED: overflow depth" severity failure;
        report "TEST PASSED"; finish;
    end process;
end architecture;
