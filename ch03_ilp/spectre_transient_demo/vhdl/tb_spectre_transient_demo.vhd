library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_spectre_transient_demo is end;
architecture test of tb_spectre_transient_demo is
 signal clk:std_logic:='0'; signal reset:std_logic:='1'; signal host_we,flush,start,mitigation_en:std_logic:='0';
 signal host_addr,host_data,index_value,probe_index:unsigned(7 downto 0):=(others=>'0'); signal bound:unsigned(8 downto 0):=(others=>'0');
 signal probe_cycles,arch_value,short_cycles,short_arch:unsigned(7 downto 0);
 signal busy,done,transient_load,transient_touch,short_busy,short_done,short_load,short_touch:std_logic;
begin
 clk<=not clk after 5 ns;
 dut:entity work.spectre_transient_demo port map(clk,reset,host_we,host_addr,host_data,flush,start,index_value,bound,mitigation_en,probe_index,probe_cycles,arch_value,busy,done,transient_load,transient_touch);
 short_path:entity work.spectre_transient_demo generic map(1) port map(clk,reset,host_we,host_addr,host_data,flush,start,index_value,bound,mitigation_en,probe_index,short_cycles,short_arch,short_busy,short_done,short_load,short_touch);
 process
  procedure init(addr,data:natural) is
  begin wait until falling_edge(clk); host_we<='1'; host_addr<=to_unsigned(addr,8); host_data<=to_unsigned(data,8); wait until falling_edge(clk); host_we<='0'; end;
  procedure run_case(idx:natural; protection:std_logic) is
  begin
   wait until falling_edge(clk); flush<='1'; start<='1'; index_value<=to_unsigned(idx,8); bound<=to_unsigned(16,9); mitigation_en<=protection;
   wait until falling_edge(clk); flush<='0'; start<='0';
   for i in 0 to 29 loop exit when done='1'; wait until falling_edge(clk); end loop;
   assert done='1' and busy='0' report "completion timeout" severity failure;
  end;
  procedure probe_all(expected_hit:integer) is
  begin
   for i in 0 to 255 loop
    probe_index<=to_unsigned(i,8); wait for 1 ns;
    if i=expected_hit then assert probe_cycles=1 report "missing cache hit" severity failure;
    else assert probe_cycles=10 report "unexpected cache hit" severity failure; end if;
   end loop;
  end;
 begin
  wait until falling_edge(clk); wait until falling_edge(clk); reset<='0'; init(3,16#33#); init(200,16#5a#);
  run_case(3,'0'); assert arch_value=x"33" and transient_load='1' and transient_touch='1' report "unprotected legal operation" severity failure; probe_all(16#33#);
  run_case(3,'1'); assert arch_value=x"33" and transient_load='0' and transient_touch='0' report "protected legal operation" severity failure; probe_all(16#33#);
  run_case(200,'0'); assert arch_value=x"33" and transient_load='1' and transient_touch='1' report "unprotected wrong path" severity failure; probe_all(16#5a#);
  probe_index<=x"5a"; wait for 1 ns; assert short_cycles=10 and short_arch=x"33" and short_touch='0' report "short speculation window" severity failure;
  run_case(200,'1'); assert arch_value=x"33" and transient_load='0' and transient_touch='0' report "protected wrong path" severity failure; probe_all(-1);
  report "TEST PASSED"; finish;
 end process;
 process begin wait for 10 us; assert false report "timeout" severity failure; wait; end process;
end architecture;
