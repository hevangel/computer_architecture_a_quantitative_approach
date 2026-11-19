library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_llsc_backoff_barrier is end;
architecture test of tb_llsc_backoff_barrier is
 signal clk:std_logic:='0'; signal reset:std_logic:='1'; signal cmd_valid,arrive:std_logic:='0';
 signal cmd_core,cmd_op,arrive_core:unsigned(1 downto 0):=(others=>'0'); signal cmd_addr:unsigned(3 downto 0):=(others=>'0');
 signal cmd_wdata:unsigned(31 downto 0):=(others=>'0'); signal rsp_valid,sc_success:std_logic;
 signal rsp_data,invalidations:unsigned(31 downto 0); signal waiting,local_sense:std_logic_vector(3 downto 0); signal global_sense,barrier_release:std_logic;
 signal done:std_logic_vector(0 to 3); type nums is array(0 to 3) of natural; signal rd,rdx,cycles,counter,cs:nums;
 function lock_mode(g:natural) return natural is begin if g=0 then return 0; elsif g=1 then return 1; elsif g=2 then return 5; else return 4; end if; end;
begin
 clk<=not clk after 5 ns;
 dut:entity work.llsc_barrier port map(clk,reset,cmd_valid,cmd_core,cmd_op,cmd_addr,cmd_wdata,rsp_valid,sc_success,rsp_data,invalidations,arrive,arrive_core,waiting,local_sense,global_sense,barrier_release);
 locks:for g in 0 to 3 generate
  lockbench:entity work.spinlock_bench generic map(P=>4,N=>8,LOCK=>lock_mode(g),CS_LEN=>12,NT=>0)
   port map(clk,not reset,done(g),rd(g),rdx(g),cycles(g),counter(g),cs(g),open,open);
  process(clk) begin if rising_edge(clk) and reset='0' then assert cs(g)<=1 report "mutual exclusion" severity failure; end if; end process;
 end generate;
 process
  procedure command(core,op,addr,data:natural; expect_sc:std_logic; expect_read:natural) is
  begin
   wait until falling_edge(clk); cmd_valid<='1'; cmd_core<=to_unsigned(core,2); cmd_op<=to_unsigned(op,2); cmd_addr<=to_unsigned(addr,4); cmd_wdata<=to_unsigned(data,32);
   wait until falling_edge(clk); cmd_valid<='0';
   assert rsp_valid='1' and sc_success=expect_sc and rsp_data=to_unsigned(expect_read,32) report "memory command response" severity failure;
  end;
  procedure arrival(core:natural) is
  begin wait until falling_edge(clk); arrive<='1'; arrive_core<=to_unsigned(core,2); wait until falling_edge(clk); arrive<='0'; end;
 begin
  wait until falling_edge(clk); wait until falling_edge(clk); reset<='0';
  command(0,1,1,0,'0',0); command(1,3,1,9,'0',0);
  assert invalidations=1 report "remote reservation invalidation" severity failure;
  command(0,2,1,7,'0',9); command(0,0,1,0,'0',9);
  command(0,1,1,0,'0',9); command(1,3,2,11,'0',0);
  command(0,2,1,7,'1',9); command(0,0,1,0,'0',7);
  command(0,2,1,8,'0',7);
  command(0,1,1,0,'0',7); command(2,1,1,0,'0',7); command(3,3,1,12,'0',7);
  assert invalidations=3 report "multi-reservation invalidation count" severity failure;
  command(2,2,1,4,'0',12);
  command(0,1,1,0,'0',12); command(0,2,2,8,'0',11); command(0,2,1,8,'0',12);
  command(3,1,1,0,'0',12); command(3,3,1,15,'0',12); command(3,2,1,8,'0',15);
  command(0,1,1,0,'0',15); command(2,1,1,0,'0',15); command(0,2,1,21,'1',15);
  command(2,2,1,8,'0',21); assert invalidations=4 report "successful SC must invalidate remote reservation" severity failure;
  arrival(0); assert waiting="0001" and global_sense='0' and barrier_release='0' report "first arrival" severity failure;
  arrival(0); assert waiting="0001" and local_sense="0001" report "duplicate arrival" severity failure;
  arrival(2); arrival(1); assert waiting="0111" and barrier_release='0' report "early barrier release" severity failure;
  arrival(3); assert waiting="0000" and global_sense='1' and barrier_release='1' and local_sense="1111" report "first barrier release" severity failure;
  arrival(3); arrival(1); arrival(0); assert waiting="1011" and global_sense='1' and barrier_release='0' report "second barrier incomplete" severity failure;
  arrival(2); assert waiting="0000" and global_sense='0' and barrier_release='1' and local_sense="0000" report "second barrier release" severity failure;
  if done/="1111" then wait until done="1111"; end if; wait until falling_edge(clk);
  for i in 0 to 3 loop assert counter(i)=32 report "lost increment" severity failure; end loop;
  assert cycles(0)=738 and cycles(1)=964 and cycles(2)=930 and cycles(3)=841 report "lock cycle counts" severity failure;
  assert rdx(3)<rdx(0) and rdx(3)<rdx(1) and rdx(3)<rdx(2) report "backoff traffic" severity failure;
  report "lock BusRdX TAS=" & integer'image(rdx(0)) & " TTAS=" & integer'image(rdx(1)) & " LRSC=" & integer'image(rdx(2)) & " backoff=" & integer'image(rdx(3));
  report "TEST PASSED"; finish;
 end process;
 process begin wait for 300 us; assert false report "timeout" severity failure; wait; end process;
end architecture;
