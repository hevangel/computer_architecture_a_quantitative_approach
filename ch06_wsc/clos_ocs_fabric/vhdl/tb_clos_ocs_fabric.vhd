library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_clos_ocs_fabric is end;
architecture test of tb_clos_ocs_fabric is
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal cfg_valid, cfg_ready : std_logic := '0';
    signal in_valid, in_ready, out_valid : std_logic_vector(31 downto 0) := (others=>'0');
    signal in_destination : std_logic_vector(95 downto 0) := (others=>'0');
    signal in_id, out_id : std_logic_vector(511 downto 0) := (others=>'0');
    signal out_ready : std_logic_vector(7 downto 0) := (others=>'0');
    signal cfg_cross, active_cross : std_logic_vector(3 downto 0) := (others=>'0');
begin
    clk<=not clk after 5 ns;
    dut: entity work.clos_ocs_fabric
        port map(clk,reset,in_valid,in_ready,in_destination,in_id,out_valid,out_ready,out_id,
                 cfg_valid,cfg_cross,cfg_ready,active_cross);
    process
        procedure tick is
        begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure traffic(adaptive, spread : boolean; variable elapsed : out natural) is
            type counters is array(0 to 31) of natural;
            variable sends : counters := (others=>0);
            variable lane_count, quota, total, got, id, dest : natural;
            variable seen : std_logic_vector(127 downto 0) := (others=>'0');
        begin
            reset<='1'; in_valid<=(others=>'0'); out_ready<=(others=>'0'); tick; reset<='0';
            if adaptive then cfg_valid<='1'; else cfg_valid<='0'; end if;
            cfg_cross<=x"1"; tick; cfg_valid<='0';
            assert (adaptive and active_cross=x"1") or (not adaptive and active_cross=x"0")
                report "initial mapping" severity failure;
            if spread then lane_count:=32; else lane_count:=4; end if;
            quota:=128/lane_count; total:=lane_count*quota;
            got:=0; elapsed:=0;
            while got<total and elapsed<300 loop
                elapsed:=elapsed+1;
                if spread and elapsed mod 5=0 then out_ready<=x"55"; else out_ready<=x"ff"; end if;
                in_valid<=(others=>'0');
                for i in 0 to lane_count-1 loop
                    if sends(i)<quota then
                        in_valid(i)<='1';
                        in_id(16*i+15 downto 16*i)<=std_logic_vector(to_unsigned(i*quota+sends(i),16));
                        if spread then dest:=(i/4+1) mod 8; else dest:=3; end if;
                        in_destination(3*i+2 downto 3*i)<=std_logic_vector(to_unsigned(dest,3));
                    end if;
                end loop;
                wait for 1 ns;
                for i in 0 to 31 loop
                    if in_ready(i)='1' and in_valid(i)='1' then sends(i):=sends(i)+1; end if;
                    if out_valid(i)='1' and out_ready(i/4)='1' then
                        id:=to_integer(unsigned(out_id(16*i+15 downto 16*i)));
                        if spread then dest:=(id/quota/4+1) mod 8; else dest:=3; end if;
                        assert id<total report "packet ID out of range" severity failure;
                        assert seen(id)='0' and i/4=dest report "duplicate or wrong destination" severity failure;
                        seen(id):='1'; got:=got+1;
                    end if;
                end loop;
                tick;
            end loop;
            assert got=total and (and seen)='1' report "loss or timeout" severity failure;
            in_valid<=(others=>'0'); tick;
            assert unsigned(out_valid)=0 report "unexpected residual egress" severity failure;
        end;
        variable static_cycles, adapted_cycles, uniform_cycles : natural;
    begin
        traffic(false,false,static_cycles);
        traffic(true,false,adapted_cycles);
        traffic(false,true,uniform_cycles);
        assert 2*static_cycles>=3*adapted_cycles report "hot-pair throughput threshold" severity failure;
        report "128 packets: fixed=" & integer'image(static_cycles) & " cycles adapted=" &
               integer'image(adapted_cycles) & " uniform=" & integer'image(uniform_cycles);

        reset<='1'; out_ready<=(others=>'0'); tick; reset<='0';
        in_valid(0)<='1'; in_destination(2 downto 0)<="011"; in_id(15 downto 0)<=x"1234"; tick;
        in_valid<=(others=>'0'); tick;
        assert out_valid(12)='1' and out_id(207 downto 192)=x"1234" report "in-flight setup" severity failure;
        cfg_valid<='1'; cfg_cross<=x"1"; tick; cfg_valid<='0';
        for k in 1 to 3 loop
            assert cfg_ready='0' and active_cross=x"0" and out_valid(12)='1' and out_id(207 downto 192)=x"1234"
                report "configuration changed under a blocked packet" severity failure;
            tick;
        end loop;
        out_ready<=x"ff"; tick;
        assert cfg_ready='1' and active_cross=x"1" and unsigned(out_valid)=0
            report "configuration did not commit on drain" severity failure;
        report "TEST PASSED";
        finish;
    end process;
    process begin wait for 10000 ns; assert false report "timeout" severity failure; end process;
end architecture;
