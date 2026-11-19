library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.env.all; use work.nb_reference_pkg.all;
entity tb_nb_set_assoc_cache is end;
architecture sim of tb_nb_set_assoc_cache is
 signal clk:std_logic:='0'; signal rst_n,req_valid,req_write,flush:std_logic:='0'; signal allow_mem:std_logic:='1';
 signal req_addr,dbg_addr,ma:natural range 0 to 255:=0; signal req_wdata,hd,fd,dbg:std_logic_vector(31 downto 0):=(others=>'0');
 signal req_id,hid,fid:natural range 0 to 63:=0; signal ready,hv,fv,flush_done,mv,mw,mready,mrv,viol:std_logic;
 signal mwd,mrl:std_logic_vector(127 downto 0); signal mt,mrt:natural range 0 to 3; signal sh,sp,ss,sw,nlw:natural;
 signal ready_gate:std_logic;
begin
 clk<=not clk after 5 ns; ready_gate<=mready and allow_mem;
 dut:entity work.wb_cache generic map(NM=>4,WBD=>2,WAYS=>2,FORWARD_WB=>true)
 port map(clk,rst_n,req_valid,req_write,req_addr,req_wdata,req_id,ready,hv,hid,hd,fv,fid,fd,flush,flush_done,mv,mw,ma,mwd,mt,ready_gate,mrv,mrt,mrl,sh,sp,ss,sw);
 mem:entity work.wb_mem port map(clk,rst_n,mv,mw,ma,mwd,mt,mready,mrv,mrt,mrl,dbg_addr,dbg,viol,nlw);
 process
  variable vector:std_logic_vector(TRACE_WIDTH-1 downto 0);
  variable ev,ew,eallow,er,ehv,efv,emv,emw:std_logic;
  variable ea,ema,ehc,epc,esc,ewc:std_logic_vector(7 downto 0);
  variable ed,ehd,efd:std_logic_vector(31 downto 0);
  variable ei,ehid,efid:std_logic_vector(5 downto 0); variable emt:std_logic_vector(1 downto 0);
  variable pri_before,sec_before,hit_before,ra:natural;
  variable seed,rv:unsigned(31 downto 0):=to_unsigned(1481,32); variable random_write:std_logic;
  type shadow_t is array(0 to 255) of std_logic_vector(31 downto 0); variable shadow:shadow_t;
  procedure request(wr:std_logic; addr:natural; data:std_logic_vector(31 downto 0); id:natural) is
  begin
   wait until falling_edge(clk); req_valid<='1'; req_write<=wr; req_addr<=addr; req_wdata<=data; req_id<=id; wait for 1 ns;
   while ready/='1' loop wait until falling_edge(clk); wait for 1 ns; end loop;
   wait until falling_edge(clk); req_valid<='0';
  end;
  procedure answer(id:natural; expected:std_logic_vector(31 downto 0)) is
   variable t:natural:=0;
  begin
   wait for 1 ns;
   while not ((hv='1' and hid=id) or (fv='1' and fid=id)) and t<80 loop wait until falling_edge(clk); wait for 1 ns; t:=t+1; end loop;
   assert t<80 report "response timeout" severity failure;
   if hv='1' and hid=id then assert hd=expected report "hit data" severity failure; else assert fd=expected report "fill data" severity failure; end if;
  end;
 begin
  for k in 1 to 3 loop wait until falling_edge(clk); end loop; rst_n<='1';
  request('1',0,x"11112222",0); for k in 1 to 20 loop wait until falling_edge(clk); end loop;
  request('1',32,x"33334444",1); for k in 1 to 20 loop wait until falling_edge(clk); end loop;
  request('0',0,x"00000000",2); answer(2,x"11112222"); assert sh=1 report "LRU hit" severity failure;
  request('0',64,x"00000000",3);
  while not (mv='1' and mw='0' and ma=64) loop wait until falling_edge(clk); end loop;
  wait until rising_edge(clk); wait until falling_edge(clk); allow_mem<='0';
  answer(3,x"5A000440"); for k in 1 to 3 loop wait until falling_edge(clk); end loop;
  request('0',32,x"00000000",4); answer(4,x"33334444");
  assert nlw=0 and viol='0' report "forwarding used memory" severity failure;
  allow_mem<='1'; for k in 1 to 30 loop wait until falling_edge(clk); end loop;
  flush<='1'; while flush_done/='1' loop wait until falling_edge(clk); end loop; wait until falling_edge(clk); flush<='0';
  dbg_addr<=0; wait for 1 ns; assert dbg=x"11112222" report "flush line 0" severity failure;
  dbg_addr<=32; wait for 1 ns; assert dbg=x"33334444" report "flush line 32" severity failure;
  assert nlw=2 and viol='0' report "writeback count" severity failure;
  request('0',0,x"00000000",5); answer(5,x"11112222"); for k in 1 to 4 loop wait until falling_edge(clk); end loop;
  pri_before:=sp; sec_before:=ss; hit_before:=sh;
  request('0',4,x"00000000",6); request('0',8,x"00000000",7); request('0',5,x"00000000",8);
  request('0',0,x"00000000",9); answer(9,x"11112222");
  answer(6,x"5A000044"); answer(8,x"5A000055"); answer(7,x"5A000088");
  assert sp-pri_before=2 and ss-sec_before=1 and sh-hit_before=1 and viol='0' report "overlapping MSHRs and hit" severity failure;
  for i in 0 to 255 loop shadow(i):=std_logic_vector(x"5A000000"+to_unsigned(i*17,32)); end loop;
  shadow(0):=x"11112222"; shadow(32):=x"33334444";
  for i in 0 to 199 loop
    seed:=resize(seed*to_unsigned(1664525,32),32)+to_unsigned(1013904223,32);
    ra:=to_integer(seed(23 downto 16)); random_write:=seed(31);
    seed:=resize(seed*to_unsigned(1664525,32),32)+to_unsigned(1013904223,32); rv:=seed;
    request(random_write,ra,std_logic_vector(rv),10);
    if random_write='1' then shadow(ra):=std_logic_vector(rv); else answer(10,shadow(ra)); end if;
  end loop;
  for k in 1 to 40 loop wait until falling_edge(clk); end loop; flush<='1';
  while flush_done/='1' loop wait until falling_edge(clk); end loop; wait until falling_edge(clk); flush<='0';
  for i in 0 to 255 loop dbg_addr<=i; wait for 1 ns; assert dbg=shadow(i) report "random flush " & integer'image(i) severity failure; end loop;
  assert viol='0' report "memory protocol" severity failure;
  rst_n<='0'; for k in 1 to 3 loop wait until falling_edge(clk); end loop; rst_n<='1';
  for step in 0 to TRACE_LENGTH-1 loop
    wait until falling_edge(clk); vector:=reference_frame(step);
    ev:=vector(171);
    ew:=vector(170);
    ea:=vector(169 downto 162);
    ed:=vector(161 downto 130);
    ei:=vector(129 downto 124);
    eallow:=vector(123);
    er:=vector(122);
    ehv:=vector(121);
    ehid:=vector(120 downto 115);
    ehd:=vector(114 downto 83);
    efv:=vector(82);
    efid:=vector(81 downto 76);
    efd:=vector(75 downto 44);
    emv:=vector(43);
    emw:=vector(42);
    ema:=vector(41 downto 34);
    emt:=vector(33 downto 32);
    ehc:=vector(31 downto 24);
    epc:=vector(23 downto 16);
    esc:=vector(15 downto 8);
    ewc:=vector(7 downto 0);
    req_valid<=ev; req_write<=ew; req_addr<=to_integer(unsigned(ea)); req_wdata<=ed; req_id<=to_integer(unsigned(ei)); allow_mem<=eallow;
    wait for 1 ns;
    assert (ev='0' or ready=er) and hv=ehv and (ehv='0' or (hid=to_integer(unsigned(ehid)) and hd=ehd)) and
      fv=efv and (efv='0' or (fid=to_integer(unsigned(efid)) and fd=efd)) and mv=emv and
      (emv='0' or (mw=emw and ma=to_integer(unsigned(ema)) and (emw='1' or mt=to_integer(unsigned(emt))))) and
      sh=to_integer(unsigned(ehc)) and sp=to_integer(unsigned(epc)) and ss=to_integer(unsigned(esc)) and sw=to_integer(unsigned(ewc)) and viol='0'
      report "reference mismatch at cycle " & integer'image(step) severity failure;
  end loop;
  report "TEST PASSED"; finish;
 end process;
 process begin wait for 100 us; assert false report "timeout" severity failure; end process;
end;
