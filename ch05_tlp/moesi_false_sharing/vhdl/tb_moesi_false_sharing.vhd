library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_moesi_false_sharing is end entity;
architecture test of tb_moesi_false_sharing is
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal valid, write : std_logic := '0';
    signal core : unsigned(1 downto 0) := (others=>'0');
    signal address : unsigned(3 downto 0) := (others=>'0');
    signal write_word, read_word, memory_writes, peer_dirty_reads, false_misses : unsigned(31 downto 0);
    signal miss_kind, requester_state : unsigned(2 downto 0);
    signal cache_states : unsigned(23 downto 0);
begin
    clk <= not clk after 5 ns;
    dut: entity work.moesi_false_sharing
        port map(clk,reset,valid,write,core,address,write_word,read_word,miss_kind,memory_writes,
                 peer_dirty_reads,false_misses,requester_state,cache_states);
    process
        procedure tick is
        begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure issue(c, a : natural; w : std_logic; data_value : natural := 0) is
        begin
            core<=to_unsigned(c,2); address<=to_unsigned(a,4); write<=w;
            write_word<=to_unsigned(data_value,32); valid<='1';
            tick;
        end;
    begin
        tick; reset<='0';
        issue(0,0,'1',13);
        assert miss_kind=1 and requester_state=3 report "initial write" severity failure;
        issue(1,0,'0');
        assert read_word=13 and memory_writes=0 and peer_dirty_reads=1 and cache_states(2 downto 0)=4
            report "owned read" severity failure;
        issue(2,0,'0');
        assert read_word=13 and memory_writes=0 and peer_dirty_reads=2 report "owned forwarding" severity failure;
        issue(0,4,'0');
        assert memory_writes=1 report "owner eviction" severity failure;
        issue(3,0,'0');
        assert read_word=13 report "backing stale" severity failure;
        issue(0,0,'0');
        assert miss_kind=3 report "conflict" severity failure;
        issue(0,2,'0'); issue(0,6,'0'); issue(0,0,'0');
        issue(0,4,'0'); issue(0,2,'0'); issue(0,0,'0');
        assert miss_kind=2 report "capacity" severity failure;
        issue(1,0,'1',99); issue(2,0,'0');
        assert miss_kind=4 and read_word=99 report "true sharing" severity failure;

        reset<='1'; valid<='0'; tick; reset<='0';
        for k in 0 to 5 loop
            issue(0,0,'1',k); issue(1,1,'1',k+10);
        end loop;
        assert false_misses=10 report "adjacent writes" severity failure;
        issue(2,0,'0');
        assert read_word=5 report "lost neighbor word" severity failure;
        reset<='1'; valid<='0'; tick; reset<='0';
        for k in 0 to 5 loop
            issue(0,0,'1',k); issue(1,2,'1',k+10);
        end loop;
        assert false_misses=0 and memory_writes=0 report "padding" severity failure;
        report "TEST PASSED";
        finish;
    end process;
end architecture;
