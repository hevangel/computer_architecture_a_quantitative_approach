library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_vector_bank_gather_strip is end;
architecture tb of tb_vector_bank_gather_strip is
 signal clk:std_logic:='0'; signal reset:std_logic:='1';
 signal mem_we,vec_we,start,indexed,store:std_logic:='0';
 signal mem_addr,vec_index,base,stride:unsigned(8 downto 0):=(others=>'0');
 signal mem_wdata,vec_wdata:std_logic_vector(31 downto 0):=(others=>'0');
 signal mem_rdata,vec_result:std_logic_vector(31 downto 0);
 signal vec_slot:unsigned(5 downto 0):=(others=>'0'); signal length:unsigned(6 downto 0):=(others=>'0');
 signal busy,done,error:std_logic; signal service_cycles,ideal_cycles,bank_stalls:unsigned(15 downto 0);
 signal strips:unsigned(2 downto 0); signal strip_length:unsigned(4 downto 0);
begin
 clk<=not clk after 5 ns;
 dut:entity work.vector_bank_gather_strip port map(clk,reset,mem_we,mem_addr,mem_wdata,mem_rdata,vec_we,vec_slot,vec_index,vec_wdata,vec_result,start,indexed,store,length,base,stride,busy,done,error,service_cycles,ideal_cycles,bank_stalls,strips,strip_length);
 process
   procedure run_vector(n:integer; ind,wr:std_logic; st:integer) is
   begin
     wait until falling_edge(clk); length<=to_unsigned(n,7); indexed<=ind; store<=wr; base<=(others=>'0'); stride<=to_unsigned(st,9); start<='1';
     wait until falling_edge(clk); start<='0';
   end;
   procedure finish_vector(svc,idl,stall,num:integer) is
   begin
     while done/='1' loop wait until falling_edge(clk); end loop;
     assert error='0' and busy='0' and service_cycles=svc and ideal_cycles=idl and bank_stalls=stall and strips=num report "statistics mismatch" severity failure;
   end;
 begin
   wait until falling_edge(clk); wait until falling_edge(clk); reset<='0';
   for i in 0 to 127 loop mem_we<='1'; mem_addr<=to_unsigned(i,9); mem_wdata<=std_logic_vector(to_unsigned(i,32)); wait until falling_edge(clk); end loop;
   mem_we<='0'; run_vector(45,'0','0',1);
   assert strip_length=16 report "first strip" severity failure;
   while strips=1 loop wait until falling_edge(clk); end loop; assert strip_length=16 report "second strip" severity failure;
   while strips=2 loop wait until falling_edge(clk); end loop; assert strip_length=13 report "third strip" severity failure;
   finish_vector(6,6,0,3);
   for i in 0 to 44 loop vec_slot<=to_unsigned(i,6); wait for 1 ns; assert vec_result=std_logic_vector(to_unsigned(i,32)) report "unit result" severity failure; end loop;
   run_vector(16,'0','0',8); finish_vector(16,2,14,1);
   for i in 0 to 15 loop vec_slot<=to_unsigned(i,6); wait for 1 ns; assert vec_result=std_logic_vector(to_unsigned(8*i,32)) report "stride result" severity failure; end loop;
   for i in 0 to 44 loop wait until falling_edge(clk); vec_we<='1'; vec_slot<=to_unsigned(i,6); vec_index<=to_unsigned((5*i) mod 113,9); vec_wdata<=std_logic_vector(to_unsigned(1000+i,32)); end loop;
   wait until falling_edge(clk); vec_we<='0'; run_vector(45,'1','1',0); finish_vector(7,6,1,3);
   for i in 0 to 44 loop mem_addr<=to_unsigned((5*i) mod 113,9); wait for 1 ns; assert mem_rdata=std_logic_vector(to_unsigned(1000+i,32)) report "scatter result" severity failure; end loop;
   run_vector(45,'1','0',0); finish_vector(7,6,1,3);
   for i in 0 to 44 loop vec_slot<=to_unsigned(i,6); wait for 1 ns; assert vec_result=std_logic_vector(to_unsigned(1000+i,32)) report "gather result" severity failure; end loop;
   for i in 0 to 1 loop wait until falling_edge(clk); vec_we<='1'; vec_slot<=to_unsigned(i,6); vec_index<=to_unsigned(7,9); vec_wdata<=std_logic_vector(to_unsigned(111+111*i,32)); end loop;
   wait until falling_edge(clk); vec_we<='0';
   run_vector(2,'1','1',0); finish_vector(2,1,1,1);
   mem_addr<=to_unsigned(7,9); wait for 1 ns; assert mem_rdata=std_logic_vector(to_unsigned(222,32)) report "duplicate scatter order" severity failure;
   run_vector(64,'0','0',1); finish_vector(8,8,0,4);
   run_vector(0,'0','0',1); assert done='1' and error='0' and busy='0' report "empty vector" severity failure;
   run_vector(65,'0','0',1); assert done='1' and error='1' and busy='0' report "oversize vector" severity failure;
   report "TEST PASSED"; finish;
 end process;
 process begin wait for 30 us; assert false report "timeout" severity failure; end process;
end architecture;
