library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_west_first_adaptive_spec_vc is end entity;
architecture test of tb_west_first_adaptive_spec_vc is
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal drive_serial : std_logic := '1';
    signal in_valid, serial_in : std_logic_vector(15 downto 0) := (others=>'0');
    signal out_ready : std_logic_vector(15 downto 0) := (others=>'1');
    signal in_ready,out_valid,serial_ready,serial_valid : std_logic_vector(15 downto 0);
    signal destination : std_logic_vector(63 downto 0) := (others=>'0');
    signal link_enable : std_logic_vector(63 downto 0) := (others=>'1');
    signal in_id : std_logic_vector(255 downto 0) := (others=>'0');
    signal out_id,serial_id : std_logic_vector(255 downto 0);
    signal link_hops,alternate_turns,serial_hops,serial_turns : unsigned(31 downto 0);
begin
    clk<=not clk after 5 ns;
    serial_in<=in_valid when drive_serial='1' else x"0000";
    dut: entity work.west_first_adaptive_spec_vc
        port map(clk,reset,in_valid,out_ready,in_ready,out_valid,destination,link_enable,in_id,out_id,
                 link_hops,alternate_turns);
    serial: entity work.west_first_adaptive_spec_vc generic map(SPECULATIVE=>false)
        port map(clk,reset,serial_in,out_ready,serial_ready,serial_valid,destination,link_enable,in_id,serial_id,
                 serial_hops,serial_turns);
    process
        procedure tick is
        begin wait until rising_edge(clk); wait for 1 ns; end;
        type counts is array(0 to 15) of natural;
        variable sent : counts := (others=>0);
        variable cycles,tag,got : natural := 0;
        variable seen : std_logic_vector(79 downto 0) := (others=>'0');
        variable was_blocked : boolean := false;
        variable blocked_id : std_logic_vector(15 downto 0);
    begin
        tick; reset<='0';
        in_valid<=x"0002"; in_id(31 downto 16)<=x"1234";
        tick; in_valid<=x"0000";
        assert out_valid=x"0000" and serial_valid=x"0000" report "early delivery" severity failure;
        tick;
        assert out_valid=x"0001" and out_id(15 downto 0)=x"1234" and serial_valid=x"0000"
            report "speculative hop latency" severity failure;
        tick;
        assert out_valid=x"0000" and serial_valid=x"0001" and serial_id(15 downto 0)=x"1234"
            report "serialized hop latency" severity failure;
        reset<='1'; tick; reset<='0'; drive_serial<='0';
        link_enable(1)<='0'; destination<=(others=>'1');
        while got<80 and cycles<500 loop
            cycles:=cycles+1;
            if cycles mod 4=0 then out_ready(15)<='0'; else out_ready(15)<='1'; end if;
            for i in 0 to 15 loop
                if sent(i)<5 then in_valid(i)<='1'; else in_valid(i)<='0'; end if;
                in_id(16*i+15 downto 16*i)<=std_logic_vector(to_unsigned(5*i+sent(i),16));
            end loop;
            wait for 1 ns;
            assert unsigned(out_valid(14 downto 0))=0 report "wrong destination" severity failure;
            if was_blocked then
                assert out_valid(15)='1' and out_id(255 downto 240)=blocked_id
                    report "unstable blocked output" severity failure;
            end if;
            for i in 0 to 15 loop
                if in_ready(i)='1' and in_valid(i)='1' then sent(i):=sent(i)+1; end if;
            end loop;
            if out_valid(15)='1' and out_ready(15)='1' then
                tag:=to_integer(unsigned(out_id(255 downto 240)));
                assert tag<80 report "invalid packet ID" severity failure;
                assert seen(tag)='0' report "duplicate packet" severity failure;
                seen(tag):='1'; got:=got+1;
            end if;
            was_blocked:=out_valid(15)='1' and out_ready(15)='0'; blocked_id:=out_id(255 downto 240);
            tick;
        end loop;
        assert got=80 and (and seen)='1' and link_hops=240 and alternate_turns>=5
            report "mesh failed to drain or took nonminimal routes" severity failure;
        in_valid<=x"0000"; out_ready<=(others=>'1'); tick;
        assert out_valid=x"0000" report "unexpected residual output" severity failure;
        report "80 packets, " & integer'image(to_integer(link_hops)) & " minimal hops, " &
               integer'image(to_integer(alternate_turns)) & " alternative turns, " & integer'image(cycles) & " cycles";
        report "TEST PASSED"; finish;
    end process;
end architecture;
