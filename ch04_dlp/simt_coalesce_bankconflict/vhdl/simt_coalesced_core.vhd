library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity simt_coalesced_core is
 generic(NW:positive:=2; WS:positive:=8; QUEUE_DEPTH:positive:=4);
 port(clk,rst_n,run,allow_request:in std_logic; imem_addr:out std_logic_vector(7 downto 0); imem_rdata:in std_logic_vector(31 downto 0);
      host_we,host_shared:in std_logic; host_addr:in unsigned(7 downto 0); host_wdata:in std_logic_vector(31 downto 0); host_rdata:out std_logic_vector(31 downto 0);
      all_done:out std_logic; stat_cycles,stat_issued,stat_lane_ops,stat_idle,transactions:out unsigned(31 downto 0));
end;
architecture rtl of simt_coalesced_core is
 signal core_reset_n:std_logic;
 signal core_addr:std_logic_vector(WS*16-1 downto 0); signal core_wdata:std_logic_vector(WS*32-1 downto 0);
 signal req_valid,req_ready,req_write,req_shared:std_logic; signal req_warp,resp_warp:unsigned(7 downto 0):=(others=>'0');
 signal req_mask:std_logic_vector(WS-1 downto 0); signal req_rd,resp_rd:unsigned(2 downto 0):=(others=>'0');
 signal addresses,wdata,rdata:std_logic_vector(1023 downto 0); signal lane_mask:std_logic_vector(31 downto 0);
 signal sys_busy,sys_done,sys_valid,sys_start:std_logic;
 signal trans:unsigned(31 downto 0):=(others=>'0');
 type addr_queue is array(0 to QUEUE_DEPTH-1) of std_logic_vector(WS*16-1 downto 0);
 type data_queue is array(0 to QUEUE_DEPTH-1) of std_logic_vector(WS*32-1 downto 0);
 type mask_queue is array(0 to QUEUE_DEPTH-1) of std_logic_vector(WS-1 downto 0);
 type warp_queue is array(0 to QUEUE_DEPTH-1) of unsigned(7 downto 0);
 type rd_queue is array(0 to QUEUE_DEPTH-1) of unsigned(2 downto 0);
 signal q_addr:addr_queue; signal q_data:data_queue; signal q_mask:mask_queue;
 signal q_warp:warp_queue; signal q_rd:rd_queue;
 signal q_shared,q_write:std_logic_vector(0 to QUEUE_DEPTH-1);
 signal head,tail:natural range 0 to QUEUE_DEPTH-1:=0;
 signal count:natural range 0 to QUEUE_DEPTH:=0;
 signal enqueue,dequeue,head_shared,head_write:std_logic;
begin
 core_reset_n<=rst_n and run;
 req_ready<='1' when run='1' and count<QUEUE_DEPTH else '0';
 enqueue<=req_valid and req_ready;
 dequeue<='1' when count>0 and sys_busy='0' else '0'; sys_start<=dequeue;
 head_shared<=q_shared(head); head_write<=q_write(head);
 transactions<=trans;
 core:entity work.simt_core generic map(NW=>NW,WS=>WS,ASYNC_MEM=>true)
  port map(clk=>clk,rst_n=>core_reset_n,imem_addr=>imem_addr,imem_rdata=>imem_rdata,dmem_addr=>core_addr,dmem_wdata=>core_wdata,
   dmem_we=>open,dmem_rdata=>(others=>'0'),all_done=>all_done,stat_cycles=>stat_cycles,stat_issued=>stat_issued,
   stat_lane_ops=>stat_lane_ops,stat_idle=>stat_idle,mem_req_valid=>req_valid,mem_req_ready=>req_ready,mem_req_write=>req_write,mem_req_shared=>req_shared,
   mem_req_warp=>req_warp,mem_req_rd=>req_rd,mem_req_mask=>req_mask,mem_resp_valid=>sys_done,mem_resp_warp=>resp_warp,mem_resp_rd=>resp_rd,mem_resp_rdata=>rdata(WS*32-1 downto 0));
 process(all)
  variable a,d:std_logic_vector(1023 downto 0); variable m:std_logic_vector(31 downto 0);
 begin
  a:=(others=>'0'); d:=(others=>'0'); m:=(others=>'0');
  for i in 0 to WS-1 loop
   a(i*32+31 downto i*32):="00000000000000" & q_addr(head)(i*16+15 downto i*16) & "00";
   d(i*32+31 downto i*32):=q_data(head)(i*32+31 downto i*32); m(i):=q_mask(head)(i);
  end loop;
  addresses<=a; wdata<=d; lane_mask<=m;
 end process;
 memory:entity work.simt_memory_system port map(clk=>clk,reset=>not rst_n,start=>sys_start,shared_mode=>head_shared,write_op=>head_write,
  allow_request=>allow_request,lane_addresses=>addresses,lane_wdata=>wdata,lane_mask=>lane_mask,host_we=>host_we,host_shared=>host_shared,host_addr=>host_addr,
  host_wdata=>host_wdata,host_rdata=>host_rdata,busy=>sys_busy,done=>sys_done,req_valid=>sys_valid,req_lane_mask=>open,
  req_line_address=>open,accepted_requests=>open,lane_rdata=>rdata);
 process(clk,rst_n)
 begin
  if rst_n='0' then resp_warp<=(others=>'0'); resp_rd<=(others=>'0'); trans<=(others=>'0'); head<=0; tail<=0; count<=0;
  elsif rising_edge(clk) then
   if enqueue='1' then
    q_addr(tail)<=core_addr; q_data(tail)<=core_wdata; q_mask(tail)<=req_mask;
    q_warp(tail)<=req_warp; q_rd(tail)<=req_rd; q_shared(tail)<=req_shared; q_write(tail)<=req_write;
    if tail=QUEUE_DEPTH-1 then tail<=0; else tail<=tail+1; end if;
   end if;
   if dequeue='1' then
    resp_warp<=q_warp(head); resp_rd<=q_rd(head);
    if head=QUEUE_DEPTH-1 then head<=0; else head<=head+1; end if;
   end if;
   if enqueue='1' and dequeue='0' then count<=count+1;
   elsif enqueue='0' and dequeue='1' then count<=count-1; end if;
   if sys_valid='1' and allow_request='1' then trans<=trans+1; end if;
  end if;
 end process;
end architecture;
