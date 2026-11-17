library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_alloy_dram_cache is end entity;
architecture test of tb_alloy_dram_cache is
    signal clk: std_logic := '0';
    signal reset: std_logic := '1';
    signal valid: std_logic := '0';
    signal address: unsigned(31 downto 0) := (others=>'0');
    signal pc: unsigned(1 downto 0) := (others=>'0');
    signal rb,rp,vb,vp,hb,hp,pb,pp: std_logic;
    signal db,dp,lb,lp,hits_b,misses_b,ch_b,cm_b,fh_b,fm_b,reads_b: unsigned(31 downto 0);
    signal hits_p,misses_p,ch_p,cm_p,fh_p,fm_p,reads_p: unsigned(31 downto 0);
begin
    clk<=not clk after 5 ns;
    baseline: entity work.alloy_dram_cache generic map(PREDICT_ENABLE=>false)
        port map(clk,reset,valid,address,pc,rb,vb,hb,pb,db,lb,hits_b,misses_b,ch_b,cm_b,fh_b,fm_b,reads_b);
    predicted: entity work.alloy_dram_cache generic map(PREDICT_ENABLE=>true)
        port map(clk,reset,valid,address,pc,rp,vp,hp,pp,dp,lp,hits_p,misses_p,ch_p,cm_p,fh_p,fm_p,reads_p);
    process
        variable elapsed,total_b,total_p: natural;
        variable seen_b,seen_p: boolean;
    begin
        wait until falling_edge(clk);
        for scenario in 0 to 1 loop
            reset<='1'; valid<='0'; wait until falling_edge(clk); reset<='0'; total_b:=0; total_p:=0;
            for i in 0 to 19 loop
                if scenario=0 then
                    if i=0 then address<=to_unsigned(0,32); pc<=to_unsigned(1,2);
                    elsif i=1 then address<=to_unsigned(0,32); pc<=to_unsigned(0,2);
                    elsif i=2 then address<=to_unsigned(0,32); pc<=to_unsigned(2,2);
                    elsif i=19 then address<=to_unsigned(4,32); pc<=to_unsigned(0,2);
                    else address<=to_unsigned(0,32); pc<=to_unsigned(0,2); end if;
                else
                    if i<3 then address<=to_unsigned(i,32); pc<=to_unsigned(1,2);
                    elsif i=19 then address<=to_unsigned(6,32); pc<=to_unsigned(0,2);
                    else address<=to_unsigned(2,32); pc<=to_unsigned(0,2); end if;
                end if;
                assert rb='1' and rp='1' report "TEST FAILED: not ready" severity failure;
                valid<='1'; wait until falling_edge(clk); valid<='0'; elapsed:=0; seen_b:=false; seen_p:=false;
                while (not seen_b or not seen_p) and elapsed<160 loop
                    wait until falling_edge(clk); elapsed:=elapsed+1;
                    if vb='1' then
                        seen_b:=true; total_b:=total_b+elapsed;
                        assert elapsed=to_integer(lb) and db=(address xor unsigned'(x"c39a57e1"))
                            report "TEST FAILED: baseline response" severity failure;
                    end if;
                    if vp='1' then
                        seen_p:=true; total_p:=total_p+elapsed;
                        assert elapsed=to_integer(lp) and dp=(address xor unsigned'(x"c39a57e1")) and hp=hb and pp=pb
                            report "TEST FAILED: predicted response" severity failure;
                    end if;
                end loop;
                assert seen_b and seen_p report "TEST FAILED: timeout" severity failure;
            end loop;
            if scenario=0 then
                assert hits_p=18 and misses_p=2 and ch_p=16 and cm_p=1 and fh_p=1 and fm_p=2 and
                       reads_b=2 and reads_p=4 and total_b=872 and total_p=843
                    report "TEST FAILED: textbook-profile accounting" severity failure;
            else
                assert hits_p=16 and misses_p=4 and ch_p=15 and cm_p=3 and fh_p=1 and fm_p=1 and
                       reads_b=4 and reads_p=5 and total_b=1064 and total_p=977
                    report "TEST FAILED: 80/15/5 accounting" severity failure;
            end if;
        end loop;
        report "TEST PASSED"; finish;
    end process;
end architecture;
