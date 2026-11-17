library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_simt_coalesce_bankconflict is end;
architecture tb of tb_simt_coalesce_bankconflict is
 signal clk:std_logic:='0'; signal reset:std_logic:='1';
 signal lane_addresses:std_logic_vector(1023 downto 0):=(others=>'0'); signal lane_mask:std_logic_vector(31 downto 0):=(others=>'0');
 signal global_transactions,shared_replay_cycles:unsigned(5 downto 0);
 signal warp,wb_warp:unsigned(2 downto 0):=(others=>'0'); signal src_a,src_b,dst,wb_reg:unsigned(4 downto 0):=(others=>'0');
 signal use_a,use_b,write_dst,issue,wb_valid,barrier_arrive:std_logic:='0';
 signal can_issue,barrier_release:std_logic; signal barrier_target:std_logic_vector(7 downto 0):=(others=>'0'); signal barrier_waiting:std_logic_vector(7 downto 0);
 signal engine_start,shared_mode,req_ready:std_logic:='0';
 signal engine_busy,engine_done,req_valid:std_logic;
 signal req_lane_mask,req_line_address:std_logic_vector(31 downto 0); signal accepted_requests:unsigned(5 downto 0);
 signal sys_start,sys_shared,sys_write,sys_allow,host_we,host_shared:std_logic:='0';
 signal host_addr:unsigned(7 downto 0):=(others=>'0'); signal host_wdata:std_logic_vector(31 downto 0):=(others=>'0');
 signal host_rdata,sys_req_mask,sys_line:std_logic_vector(31 downto 0);
 signal sys_wdata:std_logic_vector(1023 downto 0):=(others=>'0'); signal sys_rdata:std_logic_vector(1023 downto 0);
 signal sys_busy,sys_done,sys_valid:std_logic; signal sys_count:unsigned(5 downto 0);
 signal core_run,core_allow,core_host_we:std_logic:='0'; signal core_program:natural range 0 to 3:=0; signal core_done:std_logic;
 signal core_imem_addr:std_logic_vector(7 downto 0); signal core_host_addr:unsigned(7 downto 0):=(others=>'0');
 signal core_imem_data,core_host_wdata:std_logic_vector(31 downto 0):=(others=>'0'); signal core_host_rdata:std_logic_vector(31 downto 0);
 signal core_cycles,core_issued,core_ops,core_idle,core_transactions:unsigned(31 downto 0);
 function ins(op,rd,ra,rb,imm:integer) return std_logic_vector is
 begin return std_logic_vector(to_unsigned(op,5)) & std_logic_vector(to_unsigned(rd,4)) & std_logic_vector(to_unsigned(ra,4)) & std_logic_vector(to_unsigned(rb,4)) & std_logic_vector(to_unsigned(imm,15)); end;
begin
 clk<=not clk after 5 ns;
 dut:entity work.simt_coalesce_bankconflict port map(clk,reset,lane_addresses,lane_mask,global_transactions,shared_replay_cycles,warp,src_a,src_b,dst,use_a,use_b,write_dst,issue,can_issue,wb_valid,wb_warp,wb_reg,barrier_arrive,barrier_target,barrier_waiting,barrier_release);
 engine:entity work.simt_memory_engine port map(clk,reset,engine_start,shared_mode,lane_addresses,lane_mask,
    engine_busy,engine_done,req_valid,req_ready,req_lane_mask,req_line_address,accepted_requests);
 memsys:entity work.simt_memory_system port map(clk,reset,sys_start,sys_shared,sys_write,sys_allow,lane_addresses,sys_wdata,lane_mask,
   host_we,host_shared,host_addr,host_wdata,host_rdata,sys_busy,sys_done,sys_valid,sys_req_mask,sys_line,sys_count,sys_rdata);
 process(all)
 begin
  if core_program=0 then
   case core_imem_addr is
    when x"00"=>core_imem_data<=ins(7,1,0,0,0); when x"01"=>core_imem_data<=ins(8,2,1,0,0);
    when x"02"=>core_imem_data<=ins(6,3,2,0,7); when x"03"=>core_imem_data<=ins(9,0,1,3,64);
    when others=>core_imem_data<=ins(14,0,0,0,0);
   end case;
  elsif core_program=1 then
   case core_imem_addr is
    when x"00"=>core_imem_data<=ins(7,1,0,0,0); when x"01"=>core_imem_data<=ins(5,2,1,0,1);
    when x"02"=>core_imem_data<=ins(12,0,0,0,0); when x"03"=>core_imem_data<=ins(10,0,2,0,6);
    when x"04"=>core_imem_data<=ins(6,3,1,0,10); when x"05"=>core_imem_data<=ins(11,0,0,0,7);
    when x"06"=>core_imem_data<=ins(6,3,1,0,20); when x"07"=>core_imem_data<=ins(13,0,0,0,0);
    when x"08"=>core_imem_data<=ins(9,0,1,3,64); when others=>core_imem_data<=ins(14,0,0,0,0);
   end case;
  elsif core_program=2 then
   case core_imem_addr is
    when x"00"=>core_imem_data<=ins(7,1,0,0,0); when x"01"=>core_imem_data<=ins(6,5,0,0,8);
    when x"02"=>core_imem_data<=ins(3,2,1,5,0); when x"03"=>core_imem_data<=ins(6,3,1,0,20);
    when x"04"=>core_imem_data<=ins(5,7,1,0,8); when x"05"=>core_imem_data<=ins(10,0,7,0,18);
    when x"06"|x"07"|x"08"|x"09"|x"0a"|x"0b"|x"0c"|x"0d"|x"0e"|x"0f"|x"10"|x"11"=>core_imem_data<=ins(0,0,0,0,0);
    when x"12"=>core_imem_data<=ins(16,0,2,3,0); when x"13"=>core_imem_data<=ins(17,0,0,0,0);
    when x"14"=>core_imem_data<=ins(6,6,1,0,8); when x"15"=>core_imem_data<=ins(5,6,6,0,15);
    when x"16"=>core_imem_data<=ins(3,6,6,5,0); when x"17"=>core_imem_data<=ins(15,4,6,0,0);
    when x"18"=>core_imem_data<=ins(9,0,1,4,64); when x"19"=>core_imem_data<=ins(17,0,0,0,0);
    when others=>core_imem_data<=ins(14,0,0,0,0);
   end case;
  else
   case core_imem_addr is
    when x"00"=>core_imem_data<=ins(7,1,0,0,0); when x"01"=>core_imem_data<=ins(8,2,1,0,0);
    when x"02"=>core_imem_data<=ins(8,3,1,0,0); when x"03"=>core_imem_data<=ins(8,5,1,0,0);
    when x"04"=>core_imem_data<=ins(1,4,2,3,0); when x"05"=>core_imem_data<=ins(1,4,4,5,0);
    when x"06"=>core_imem_data<=ins(9,0,1,4,64); when others=>core_imem_data<=ins(14,0,0,0,0);
   end case;
  end if;
 end process;
 integrated:entity work.simt_coalesced_core port map(clk,not reset,core_run,core_allow,core_imem_addr,core_imem_data,
   core_host_we,'0',core_host_addr,core_host_wdata,core_host_rdata,core_done,core_cycles,core_issued,core_ops,core_idle,core_transactions);
 process
  procedure arrive(w:integer) is
  begin wait until falling_edge(clk); warp<=to_unsigned(w,3); barrier_arrive<='1'; wait until falling_edge(clk); barrier_arrive<='0'; end;
  variable m:std_logic_vector(31 downto 0); variable count:integer;
 begin
  wait until falling_edge(clk); wait until falling_edge(clk); reset<='0';
  for k in 0 to 2 loop
   count:=8*(2**k); m:=(others=>'0');
   for i in 0 to 31 loop if i<count then m(i):='1'; end if; lane_addresses(i*32+31 downto i*32)<=std_logic_vector(to_unsigned(i*4,32)); end loop;
   lane_mask<=m; wait for 1 ns;
   assert global_transactions=(count+15)/16 and shared_replay_cycles=1 report "contiguous mismatch" severity failure;
   for i in 0 to 31 loop lane_addresses(i*32+31 downto i*32)<=std_logic_vector(to_unsigned(i*64,32)); end loop;
   wait for 1 ns; assert global_transactions=count report "stride mismatch" severity failure;
  end loop;
  lane_mask<=(others=>'1');
  for i in 0 to 31 loop lane_addresses(i*32+31 downto i*32)<=std_logic_vector(to_unsigned((i mod 8)*4+(i/8)*128,32)); end loop;
  wait for 1 ns; assert shared_replay_cycles=4 report "bank conflict" severity failure;
  lane_mask<=(others=>'0'); wait for 1 ns; assert global_transactions=0 and shared_replay_cycles=0 report "empty mask" severity failure;
  wait until falling_edge(clk); warp<=to_unsigned(0,3); dst<=to_unsigned(5,5); write_dst<='1'; issue<='1';
  wait until falling_edge(clk); issue<='0'; write_dst<='0'; src_a<=to_unsigned(5,5); use_a<='1'; wait for 1 ns;
  assert can_issue='0' report "RAW hazard not blocked" severity failure;
  warp<=to_unsigned(1,3); wait for 1 ns; assert can_issue='1' report "other warp blocked" severity failure;
  warp<=to_unsigned(0,3); wb_warp<=to_unsigned(0,3); wb_reg<=to_unsigned(5,5); wb_valid<='1';
  wait until falling_edge(clk); wb_valid<='0'; wait for 1 ns; assert can_issue='1' report "writeback failed" severity failure;
  use_a<='0'; barrier_target<=x"0f";
  for phase in 0 to 1 loop
   arrive(0); assert barrier_waiting=x"01" and barrier_release='0' report "barrier first" severity failure;
   wait for 1 ns; assert can_issue='0' report "barrier warp issued" severity failure;
   arrive(1); arrive(2); assert barrier_waiting=x"07" report "barrier incomplete" severity failure;
   arrive(3); assert barrier_release='1' and barrier_waiting=x"00" report "barrier release" severity failure;
  end loop;
  lane_mask<=(others=>'1');
  for i in 0 to 31 loop lane_addresses(i*32+31 downto i*32)<=std_logic_vector(to_unsigned(i*4,32)); end loop;
  wait until falling_edge(clk); engine_start<='1'; shared_mode<='0'; wait until falling_edge(clk); engine_start<='0';
  assert req_valid='1' and req_line_address=x"00000000" and req_lane_mask=x"0000ffff" report "first line" severity failure;
  for i in 1 to 2 loop wait until falling_edge(clk);
    assert req_valid='1' and req_lane_mask=x"0000ffff" and req_line_address=x"00000000" report "stalled line" severity failure;
  end loop;
  req_ready<='1'; wait until falling_edge(clk);
  assert req_valid='1' and req_line_address=x"00000040" and req_lane_mask=x"ffff0000" report "second line" severity failure;
  wait until falling_edge(clk); req_ready<='0';
  assert engine_done='1' and engine_busy='0' and accepted_requests=2 report "coalescer completion" severity failure;
  for i in 0 to 31 loop lane_addresses(i*32+31 downto i*32)<=std_logic_vector(to_unsigned(i*64,32)); end loop;
  wait until falling_edge(clk); engine_start<='1'; wait until falling_edge(clk); engine_start<='0'; req_ready<='1';
  for i in 0 to 31 loop
    assert req_valid='1' and req_line_address=std_logic_vector(to_unsigned(i*64,32)) and
           req_lane_mask=std_logic_vector(shift_left(to_unsigned(1,32),i)) report "uncoalesced request" severity failure;
    wait until falling_edge(clk);
  end loop;
  req_ready<='0'; assert engine_done='1' and accepted_requests=32 report "uncoalesced completion" severity failure;
  for i in 0 to 31 loop lane_addresses(i*32+31 downto i*32)<=std_logic_vector(to_unsigned((i mod 8)*4+(i/8)*128,32)); end loop;
  wait until falling_edge(clk); shared_mode<='1'; engine_start<='1'; wait until falling_edge(clk); engine_start<='0'; req_ready<='1';
  for round in 0 to 3 loop
    assert req_valid='1' and req_lane_mask=std_logic_vector(shift_left(to_unsigned(255,32),8*round)) report "shared replay" severity failure;
    wait until falling_edge(clk);
  end loop;
  req_ready<='0'; assert engine_done='1' and accepted_requests=4 report "shared completion" severity failure;
  lane_mask<=(others=>'0'); wait until falling_edge(clk); engine_start<='1'; wait until falling_edge(clk); engine_start<='0';
  assert engine_done='1' and engine_busy='0' and accepted_requests=0 report "empty request" severity failure;
  for i in 0 to 31 loop
   wait until falling_edge(clk); host_we<='1'; host_shared<='0'; host_addr<=to_unsigned(i,8); host_wdata<=std_logic_vector(to_unsigned(500+i,32));
  end loop;
  wait until falling_edge(clk); host_we<='0'; lane_mask<=(others=>'1');
  for i in 0 to 31 loop lane_addresses(i*32+31 downto i*32)<=std_logic_vector(to_unsigned(i*4,32)); end loop;
  wait until falling_edge(clk); sys_start<='1'; sys_shared<='0'; sys_write<='0'; sys_allow<='0';
  wait until falling_edge(clk); sys_start<='0';
  for j in 1 to 2 loop wait until falling_edge(clk);
   assert sys_valid='1' and sys_line=x"00000000" and sys_req_mask=x"0000ffff" report "system stall" severity failure;
  end loop;
  sys_allow<='1'; while sys_done/='1' loop wait until falling_edge(clk); end loop; sys_allow<='0';
  assert sys_count=2 report "global count" severity failure;
  for i in 0 to 31 loop assert sys_rdata(i*32+31 downto i*32)=std_logic_vector(to_unsigned(500+i,32)) report "global data" severity failure; end loop;
  for i in 0 to 31 loop
   lane_addresses(i*32+31 downto i*32)<=std_logic_vector(to_unsigned((i mod 8)*4+(i/8)*128,32));
   sys_wdata(i*32+31 downto i*32)<=std_logic_vector(to_unsigned(1000+i,32));
  end loop;
  wait until falling_edge(clk); sys_start<='1'; sys_shared<='1'; sys_write<='1'; sys_allow<='1';
  wait until falling_edge(clk); sys_start<='0'; while sys_done/='1' loop wait until falling_edge(clk); end loop; sys_allow<='0';
  assert sys_count=4 report "shared store count" severity failure;
  wait until falling_edge(clk); sys_start<='1'; sys_write<='0'; sys_allow<='1';
  wait until falling_edge(clk); sys_start<='0'; while sys_done/='1' loop wait until falling_edge(clk); end loop; sys_allow<='0';
  assert sys_count=4 report "shared load count" severity failure;
  for i in 0 to 31 loop assert sys_rdata(i*32+31 downto i*32)=std_logic_vector(to_unsigned(1000+i,32)) report "shared data" severity failure; end loop;
  lane_mask<=x"55555555";
  for i in 0 to 31 loop
   lane_addresses(i*32+31 downto i*32)<=std_logic_vector(to_unsigned(i*4,32));
   sys_wdata(i*32+31 downto i*32)<=std_logic_vector(to_unsigned(2000+i,32));
  end loop;
  wait until falling_edge(clk); sys_start<='1'; sys_shared<='0'; sys_write<='1'; sys_allow<='1';
  wait until falling_edge(clk); sys_start<='0'; while sys_done/='1' loop wait until falling_edge(clk); end loop; sys_allow<='0';
  assert sys_count=2 report "masked store count" severity failure;
  host_shared<='0';
  for i in 0 to 31 loop
   host_addr<=to_unsigned(i,8); wait for 1 ns;
   if i mod 2=0 then assert host_rdata=std_logic_vector(to_unsigned(2000+i,32)) report "masked store data" severity failure;
   else assert host_rdata=std_logic_vector(to_unsigned(500+i,32)) report "inactive data" severity failure; end if;
  end loop;
  for i in 0 to 15 loop
   wait until falling_edge(clk); core_host_we<='1'; core_host_addr<=to_unsigned(i,8); core_host_wdata<=std_logic_vector(to_unsigned(i,32));
  end loop;
  wait until falling_edge(clk); core_host_we<='0'; core_run<='1';
  for i in 0 to 199 loop
   exit when core_done='1';
   if i mod 3/=0 then core_allow<='1'; else core_allow<='0'; end if;
   wait until falling_edge(clk);
  end loop;
  assert core_done='1' and core_transactions=4 and core_issued=10 and core_ops=80 report "integrated core statistics" severity failure;
  for i in 0 to 15 loop
   core_host_addr<=to_unsigned(64+i,8); wait for 1 ns;
   assert core_host_rdata=std_logic_vector(to_unsigned(i+7,32)) report "integrated core result" severity failure;
  end loop;
  wait until falling_edge(clk); core_run<='0'; core_program<=1;
  wait until falling_edge(clk); core_run<='1'; core_allow<='1';
  for i in 0 to 199 loop exit when core_done='1'; wait until falling_edge(clk); end loop;
  assert core_done='1' and core_transactions=6 and core_issued=22 report "divergent core statistics" severity failure;
  for i in 0 to 15 loop
   core_host_addr<=to_unsigned(64+i,8); wait for 1 ns;
   if i mod 2=0 then assert core_host_rdata=std_logic_vector(to_unsigned(i+20,32)) report "even divergent result" severity failure;
   else assert core_host_rdata=std_logic_vector(to_unsigned(i+10,32)) report "odd divergent result" severity failure; end if;
  end loop;
  wait until falling_edge(clk); core_run<='0'; core_program<=2; wait until falling_edge(clk); core_run<='1'; core_allow<='1';
  for i in 0 to 299 loop
   exit when core_done='1';
   if i mod 4=0 then core_allow<='0'; else core_allow<='1'; end if;
   wait until falling_edge(clk);
  end loop;
  assert core_done='1' and core_transactions=16 and core_issued=42 report "shared/barrier statistics" severity failure;
  for i in 0 to 15 loop
   core_host_addr<=to_unsigned(64+i,8); wait for 1 ns;
   assert core_host_rdata=std_logic_vector(to_unsigned(((i+8) mod 16)+20,32)) report "cross-warp shared result" severity failure;
  end loop;
  wait until falling_edge(clk); core_run<='0'; core_program<=3; core_allow<='0';
  wait until falling_edge(clk); core_run<='1';
  for i in 1 to 25 loop wait until falling_edge(clk); end loop;
  assert core_issued=7 and core_transactions=16 and core_done='0' report "queued loads did not overlap" severity failure;
  core_allow<='1';
  for i in 0 to 199 loop exit when core_done='1'; wait until falling_edge(clk); end loop;
  assert core_done='1' and core_transactions=24 and core_issued=16 and core_ops=128 report "queued program statistics" severity failure;
  for i in 0 to 15 loop
   core_host_addr<=to_unsigned(64+i,8); wait for 1 ns;
   assert core_host_rdata=std_logic_vector(to_unsigned(3*i,32)) report "queued result" severity failure;
  end loop;
  report "TEST PASSED"; finish;
 end process;
 process begin wait for 10 us; assert false report "timeout" severity failure; end process;
end architecture;
