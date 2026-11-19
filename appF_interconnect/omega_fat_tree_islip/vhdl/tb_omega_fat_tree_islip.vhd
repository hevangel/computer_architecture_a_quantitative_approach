library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_omega_fat_tree_islip is end entity;
architecture test of tb_omega_fat_tree_islip is
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal advance : std_logic := '0';
    signal in_valid, in_tail, out_ready : std_logic_vector(7 downto 0) := x"00";
    signal in_ready, out_valid, out_tail : std_logic_vector(7 downto 0);
    signal in_dest : std_logic_vector(23 downto 0) := (others=>'0');
    signal in_data, out_data : std_logic_vector(127 downto 0) := (others=>'0');
    signal requests : std_logic_vector(63 downto 0) := (others=>'0');
    signal iterative, baseline : std_logic_vector(63 downto 0);
    function destination(src : natural; blocks : boolean) return natural is
    begin
        if blocks then return 4*(src mod 2)+2*((src/2) mod 2)+src/4; end if;
        return 4*(src mod 2)+2*(src/4)+(src/2) mod 2;
    end;
begin
    clk<=not clk after 5 ns;
    network: entity work.omega8 port map(clk,reset,in_valid,in_tail,in_ready,in_dest,in_data,
                                        out_valid,out_tail,out_ready,out_data);
    round4: entity work.islip8 port map(clk,reset,advance,requests,iterative);
    round1: entity work.islip8 generic map(ITERATIONS=>1) port map(clk,reset,advance,requests,baseline);
    process
        procedure tick is
        begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure traffic(blocks : boolean; variable cycles : out natural) is
            type counts is array(0 to 7) of natural;
            variable sent, received : counts := (others=>0);
            variable tag, src, word_id, total : integer;
            variable was_stalled : std_logic_vector(7 downto 0) := x"00";
            variable stalled_data : std_logic_vector(127 downto 0) := (others=>'0');
        begin
            reset<='1'; in_valid<=x"00"; out_ready<=x"00"; tick; reset<='0';
            total:=0; cycles:=0;
            while total<24 and cycles<200 loop
                cycles:=cycles+1;
                if cycles mod 7=0 then out_ready<=x"55"; else out_ready<=x"ff"; end if;
                in_valid<=x"00"; in_tail<=x"00";
                for i in 0 to 7 loop
                    if sent(i)<3 then
                        in_valid(i)<='1';
                        if sent(i)=2 then in_tail(i)<='1'; end if;
                        in_dest(3*i+2 downto 3*i)<=std_logic_vector(to_unsigned(destination(i,blocks),3));
                        in_data(16*i+15 downto 16*i)<=std_logic_vector(to_unsigned(16*(i+1)+sent(i),16));
                    end if;
                end loop;
                wait for 1 ns;
                for i in 0 to 7 loop
                    if was_stalled(i)='1' then
                        assert out_valid(i)='1' and out_data(16*i+15 downto 16*i)=stalled_data(16*i+15 downto 16*i)
                            report "unstable stalled packet" severity failure;
                    end if;
                    if in_ready(i)='1' and in_valid(i)='1' then sent(i):=sent(i)+1; end if;
                    if out_valid(i)='1' and out_ready(i)='1' then
                        tag:=to_integer(unsigned(out_data(16*i+15 downto 16*i)));
                        src:=tag/16-1; word_id:=tag mod 16;
                        assert src>=0 and src<8 report "invalid packet source" severity failure;
                        assert destination(src,blocks)=i and received(src)=word_id and word_id<3
                            report "loss, misroute, or broken wormhole ordering" severity failure;
                        assert (out_tail(i)='1')=(word_id=2) report "tail mismatch" severity failure;
                        received(src):=received(src)+1; total:=total+1;
                    end if;
                end loop;
                was_stalled:=out_valid and not out_ready; stalled_data:=out_data;
                tick;
            end loop;
            assert total=24 report "drain timeout" severity failure;
            in_valid<=x"00"; tick;
            assert out_valid=x"00" report "unexpected output after drain" severity failure;
        end;
        variable free_cycles, blocked_cycles : natural;
        variable accepted_one, accepted_four : natural := 0;
    begin
        traffic(false,free_cycles);
        traffic(true,blocked_cycles);
        assert blocked_cycles>free_cycles report "blocking was not observed" severity failure;
        report "24 flits: nonblocking=" & integer'image(free_cycles) &
               " cycles, transpose=" & integer'image(blocked_cycles) & " cycles";
        reset<='1'; tick; reset<='0';
        requests<=x"0000000000000203"; wait for 1 ns;
        assert baseline=x"0000000000000001" and iterative=x"0000000000000201"
            report "additional iSLIP iteration did not fill idle port" severity failure;
        advance<='1'; tick;
        assert baseline=x"0000000000000002" and iterative=baseline
            report "first iteration pointers incorrect" severity failure;
        requests<=x"0000000000000202"; wait for 1 ns;
        assert baseline=x"0000000000000002" and iterative=baseline
            report "later-round pointer update must be deferred" severity failure;
        tick;
        assert baseline=x"0000000000000200" and iterative=baseline
            report "grant pointer fairness" severity failure;
        reset<='1'; advance<='0'; tick; reset<='0';
        for sample in 0 to 31 loop
            case sample mod 4 is
                when 0 => requests<=x"0000000000000203";
                when 1 => requests<=x"0303020203030202";
                when 2 => requests<=x"030f030f030f030f";
                when others => requests<=x"0703030105030107";
            end case;
            wait for 1 ns;
            assert unsigned(iterative and not requests)=0 and unsigned(baseline and not requests)=0
                report "unsolicited match" severity failure;
            for b in 0 to 63 loop
                if baseline(b)='1' then accepted_one:=accepted_one+1; end if;
                if iterative(b)='1' then accepted_four:=accepted_four+1; end if;
            end loop;
            advance<='1'; tick;
        end loop;
        assert accepted_one=76 and accepted_four=86 report "crossbar utilization" severity failure;
        report "32 crossbar samples: one round=" & integer'image(accepted_one) &
               ", four rounds=" & integer'image(accepted_four);
        report "TEST PASSED"; finish;
    end process;
    process begin wait for 10000 ns; assert false report "timeout" severity failure; end process;
end architecture;
