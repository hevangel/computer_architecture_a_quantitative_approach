library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;
entity tb_tage_predictor is end;
architecture test of tb_tage_predictor is
 signal clk:std_logic:='0'; signal reset:std_logic:='1'; signal pc:unsigned(15 downto 0):=(others=>'0');
 signal update_valid,actual_taken:std_logic:='0'; signal prediction,gshare_prediction:std_logic;
 signal provider:unsigned(1 downto 0); signal history:unsigned(17 downto 0);
begin
 clk<=not clk after 5 ns;
 dut:entity work.tage_predictor port map(clk,reset,pc,update_valid,actual_taken,prediction,gshare_prediction,provider,history);
 process
  file vectors:text open read_mode is "../../../../ch03_ilp/tage_predictor/golden.txt";
  variable ln:line; variable vpc:std_logic_vector(15 downto 0); variable expected:std_logic_vector(7 downto 0);
  variable old_history:unsigned(17 downto 0); variable te,ge,long_provider:integer:=0;
 begin
  wait until falling_edge(clk); wait until falling_edge(clk); reset<='0';
  for i in 0 to 7023 loop
   assert not endfile(vectors) report "short vectors" severity failure;
   readline(vectors,ln); hread(ln,vpc); hread(ln,expected);
   pc<=unsigned(vpc); actual_taken<=expected(0); wait for 1 ns;
   assert prediction=expected(1) and gshare_prediction=expected(2) and provider=unsigned(expected(4 downto 3))
     report "prediction vector " & integer'image(i) severity failure;
   if i>=4000 and i<6000 then
    if prediction/=expected(0) then te:=te+1; end if;
    if gshare_prediction/=expected(0) then ge:=ge+1; end if;
    if provider=3 then long_provider:=long_provider+1; end if;
   end if;
   if i mod 113=0 then
    old_history:=history; update_valid<='0'; wait until falling_edge(clk); wait for 1 ns;
    assert history=old_history and prediction=expected(1) and gshare_prediction=expected(2) and provider=unsigned(expected(4 downto 3))
      report "disabled update" severity failure;
   end if;
   update_valid<='1'; wait until falling_edge(clk); update_valid<='0';
  end loop;
  assert endfile(vectors) report "extra vectors" severity failure;
  assert te=0 and ge=125 and long_provider=250 report "long-history error counts" severity failure;
  report "TEST PASSED TAGE=" & integer'image(te) & " gshare=" & integer'image(ge); finish;
 end process;
 process begin wait for 150 us; assert false report "timeout" severity failure; wait; end process;
end architecture;
