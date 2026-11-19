library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

entity tb_tensor_core_sparse24_fp8 is end entity;
architecture test of tb_tensor_core_sparse24_fp8 is
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal start, sparse : std_logic := '0';
    signal format : unsigned(1 downto 0) := (others=>'0');
    signal scale_a, scale_b : signed(7 downto 0) := (others=>'0');
    signal a_tile : unsigned(255 downto 0) := (others=>'0');
    signal c_tile, d_tile : unsigned(511 downto 0) := (others=>'0');
    signal indices : unsigned(15 downto 0) := (others=>'0');
    signal dense_weights : unsigned(255 downto 0) := (others=>'0');
    signal sparse_weights : unsigned(127 downto 0) := (others=>'0');
    signal weights : unsigned(63 downto 0);
    signal weight_read, busy, done, error : std_logic;
    signal weight_slot : unsigned(1 downto 0);
    signal compute_cycles : unsigned(2 downto 0);
    signal weight_reads, flags : unsigned(4 downto 0);
begin
    clk<=not clk after 5 ns;
    dut: entity work.tensor_core_sparse24_fp8
        port map(clk,reset,start,sparse,format,scale_a,scale_b,a_tile,c_tile,indices,
                 weight_read,weight_slot,weights,busy,done,error,compute_cycles,weight_reads,flags,d_tile);
    process(all)
        variable slot : natural;
    begin
        weights <= (others=>'0');
        if not is_x(std_logic_vector(weight_slot)) then
            slot := to_integer(weight_slot);
            if sparse='0' then weights<=dense_weights(64*slot+63 downto 64*slot);
            elsif slot<2 then weights<=sparse_weights(64*slot+63 downto 64*slot); end if;
        end if;
    end process;

    process
        file vectors : text open read_mode is "../../../../ch07_dsa/tensor_core_sparse24_fp8/vectors.txt";
        variable row : line;
        variable fmt, sa, sb : integer;
        variable av, bv : std_logic_vector(255 downto 0);
        variable cv, expected_d : std_logic_vector(511 downto 0);
        variable compact : std_logic_vector(127 downto 0);
        variable mapping : std_logic_vector(15 downto 0);
        variable expected_flags : std_logic_vector(7 downto 0);
        variable count, beats, reads, expected_beats : natural := 0;
        procedure tick is
        begin wait until rising_edge(clk); wait for 1 ns; end;
    begin
        tick; reset<='0';
        while not endfile(vectors) loop
            readline(vectors,row);
            read(row,fmt); read(row,sa); read(row,sb);
            hread(row,av); hread(row,cv); hread(row,bv); hread(row,compact);
            hread(row,mapping); hread(row,expected_d); hread(row,expected_flags);
            format<=to_unsigned(fmt,2); scale_a<=to_signed(sa,8); scale_b<=to_signed(sb,8);
            a_tile<=unsigned(av); c_tile<=unsigned(cv);
            dense_weights<=unsigned(bv); sparse_weights<=unsigned(compact);
            indices<=unsigned(mapping);
            for mode in 0 to 1 loop
                if mode=0 then sparse<='0'; expected_beats:=4; else sparse<='1'; expected_beats:=2; end if;
                start<='1'; tick; start<='0'; beats:=0; reads:=0;
                while busy='1' and beats<5 loop
                    assert weight_read='1' and weight_slot=beats report "weight address" severity failure;
                    reads:=reads+4; beats:=beats+1; tick;
                end loop;
                assert done='1' and error='0' and weight_read='0' and
                       d_tile=unsigned(expected_d) and flags=unsigned(expected_flags(4 downto 0))
                    report "tile mismatch case " & integer'image(count) & " sparse " & integer'image(mode)
                    severity failure;
                assert beats=expected_beats and compute_cycles=beats and weight_reads=reads
                    report "wrong compute or read count" severity failure;
            end loop;
            count:=count+1;
        end loop;
        indices(3 downto 0)<="0101"; sparse<='1'; start<='1'; tick; start<='0';
        assert done='1' and error='1' and busy='0' and weight_read='0' and weight_reads=0 and d_tile=c_tile
            report "duplicate metadata accepted" severity failure;
        indices(3 downto 0)<="0110"; start<='1'; tick; start<='0';
        assert done='1' and error='1' and busy='0' and weight_read='0' and compute_cycles=0
            report "descending metadata accepted" severity failure;
        sparse<='0'; format<="00"; start<='1'; tick; start<='0';
        assert done='1' and error='1' and busy='0' and weight_read='0'
            report "unsupported input format accepted" severity failure;
        tick;
        assert done='0' and count=30 report "done or case count" severity failure;
        report "TEST PASSED (" & integer'image(count) & " dense/sparse pairs)";
        finish;
    end process;
end architecture;
