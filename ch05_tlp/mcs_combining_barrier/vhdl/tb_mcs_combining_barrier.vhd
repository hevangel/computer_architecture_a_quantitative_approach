library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mcs_case is
    generic(N : positive);
    port(done : out boolean := false);
end entity;
architecture test of mcs_case is
    subtype cores is std_logic_vector(N-1 downto 0);
    constant ZERO_BITS : cores := (others=>'0');
    constant ALL_BITS : cores := (others=>'1');
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal request, unlock, arrive : cores := ZERO_BITS;
    signal queued_owner, central_owner, tree_release, central_release : cores;
    signal queue_handoff, central_handoff, tree_messages, root_tree, central_messages, root_central : unsigned(31 downto 0);
    function bit_at(i : natural) return cores is
    begin return std_logic_vector(to_unsigned(2**i,N)); end;
    function log2(v : positive) return natural is
        variable bits : natural := 0;
        variable value : natural := v;
    begin
        while value>1 loop bits:=bits+1; value:=value/2; end loop;
        return bits;
    end;
begin
    clk <= not clk after 5 ns;
    tree: entity work.mcs_combining_barrier generic map(N=>N)
        port map(clk,reset,request,unlock,arrive,queued_owner,tree_release,queue_handoff,tree_messages,root_tree);
    central: entity work.mcs_combining_barrier generic map(N=>N,TREE=>false,MCS=>false)
        port map(clk,reset,request,unlock,arrive,central_owner,central_release,central_handoff,central_messages,root_central);
    process
        procedure tick is
        begin
            wait until rising_edge(clk); wait for 1 ns;
            assert (unsigned(queued_owner) and (unsigned(queued_owner)-1))=0 and
                   (unsigned(central_owner) and (unsigned(central_owner)-1))=0
                report "mutual exclusion" severity failure;
        end procedure;
        variable expected : integer;
    begin
        tick; reset<='0';
        request<=bit_at(0); tick;
        request<=bit_at(1); unlock<=bit_at(0); tick;
        assert queued_owner=bit_at(0) and central_owner=bit_at(1) report "late link wait" severity failure;
        request<=ZERO_BITS; unlock<=ZERO_BITS; tick;
        assert queued_owner=bit_at(1) and queue_handoff=1 report "late link handoff" severity failure;
        unlock<=bit_at(1); tick;
        assert queued_owner=ZERO_BITS and central_owner=ZERO_BITS report "uncontended release" severity failure;
        reset<='1'; unlock<=ZERO_BITS; tick; reset<='0';
        request<=bit_at(0); tick; request<=not bit_at(0); tick; request<=ZERO_BITS;
        for i in 1 to N loop tick; end loop;
        for i in 0 to N-1 loop
            assert queued_owner=bit_at(i) and central_owner=bit_at(i) report "FIFO/order" severity failure;
            unlock<=bit_at(i); tick;
            if i+1<N then expected:=i+1; else expected:=N-1; end if;
            assert queue_handoff=expected and central_handoff=(i+1)*(2*N-2-i)/2
                report "handoff traffic" severity failure;
        end loop;
        assert queued_owner=ZERO_BITS and central_owner=ZERO_BITS report "lock did not drain" severity failure;
        unlock<=ZERO_BITS;
        for phase in 0 to 1 loop
            for i in 0 to N-2 loop
                if phase=0 then arrive<=bit_at(i); else arrive<=bit_at(N-1-i); end if;
                tick;
                assert tree_release=ZERO_BITS and central_release=ZERO_BITS report "early release" severity failure;
            end loop;
            tick;
            if phase=0 then arrive<=bit_at(N-1); else arrive<=bit_at(0); end if;
            tick; arrive<=ZERO_BITS;
            assert tree_release=ZERO_BITS and central_release=ZERO_BITS report "last arrival edge" severity failure;
            for step in 1 to 2*log2(N)+1 loop
                tick;
                if step=1 then
                    assert central_release=ALL_BITS report "central release" severity failure;
                else
                    assert central_release=ZERO_BITS report "central pulse" severity failure;
                end if;
                if step=2*log2(N)+1 then
                    assert tree_release=ALL_BITS report "tree release" severity failure;
                else
                    assert tree_release=ZERO_BITS report "tree early release" severity failure;
                end if;
            end loop;
            assert tree_messages=(phase+1)*4*(N-1) and root_tree=(phase+1)*4 and
                   central_messages=(phase+1)*2*N and root_central=central_messages
                report "barrier traffic" severity failure;
            tick;
            assert tree_release=ZERO_BITS and central_release=ZERO_BITS report "release was not a pulse" severity failure;
        end loop;
        report "N=" & integer'image(N) & " handoff " & to_string(queue_handoff) & "/" &
               to_string(central_handoff) & " barrier root " & to_string(root_tree) & "/" & to_string(root_central);
        done<=true;
        wait;
    end process;
end architecture;

library ieee;
use std.env.all;
entity tb_mcs_combining_barrier is end;
architecture test of tb_mcs_combining_barrier is
    signal d2,d4,d8 : boolean;
begin
    case2: entity work.mcs_case generic map(N=>2) port map(d2);
    case4: entity work.mcs_case generic map(N=>4) port map(d4);
    case8: entity work.mcs_case generic map(N=>8) port map(d8);
    process begin
        wait until d2 and d4 and d8 for 2000 ns;
        assert d2 and d4 and d8 report "timeout" severity failure;
        report "TEST PASSED";
        finish;
    end process;
end architecture;
