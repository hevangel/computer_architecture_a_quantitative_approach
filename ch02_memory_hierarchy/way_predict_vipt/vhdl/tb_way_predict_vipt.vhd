library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.env.all;
entity tb_way_predict_vipt is end;
architecture sim of tb_way_predict_vipt is
 signal clk:std_logic:='0'; signal reset:std_logic:='1'; signal valid,wr,bad_valid:std_logic:='0';
 signal va,pa,dbg_addr:unsigned(15 downto 0):=(others=>'0'); signal wd:unsigned(31 downto 0):=(others=>'0');
 signal ready,rv,fault,safe,busy,bad_ready,bad_rv,bad_fault,bad_safe:std_logic; signal word:unsigned(1 downto 0);
 signal rd,fast,slow,miss,probes,dbg,bad_data:unsigned(31 downto 0);
begin
 clk<=not clk after 5 ns;
 dut:entity work.way_predict_vipt port map(clk,reset,valid,wr,va,pa,wd,ready,rv,fault,rd,safe,busy,word,fast,slow,miss,probes,dbg_addr,dbg);
 bad:entity work.way_predict_vipt generic map(PAGE_BITS=>5) port map(clk,reset,bad_valid,'0',x"0000",x"0000",x"00000000",bad_ready,bad_rv,bad_fault,bad_data,bad_safe,open,open,open,open,open,open,x"0000",open);
 process
  procedure access_cache(w:std_logic; v,p:unsigned(15 downto 0); data,expected:unsigned(31 downto 0); latency:natural; is_fault:std_logic) is
   variable cycles,n,first:natural;
  begin
   wait until falling_edge(clk); while ready/='1' loop wait until falling_edge(clk); end loop;
   va<=v; pa<=p; wd<=data; wr<=w; valid<='1'; first:=to_integer(v(3 downto 2)); n:=0; cycles:=0;
   wait until falling_edge(clk); valid<='0'; cycles:=1; wait for 1 ns;
   while rv/='1' and cycles<20 loop
    if busy='1' then assert to_integer(word)=(first+n) mod 4 report "refill order" severity failure; n:=n+1; end if;
    wait until falling_edge(clk); wait for 1 ns; cycles:=cycles+1;
   end loop;
   assert rv='1' and fault=is_fault and (is_fault='1' or rd=expected) and (latency=0 or cycles=latency)
    report "response/latency at " & integer'image(to_integer(v)) & " got " & integer'image(cycles) & " expected " & integer'image(latency) severity failure;
   if latency=3 then assert busy='1' and ready='0' report "critical response not early" severity failure; end if;
   while ready/='1' loop
    if busy='1' then assert to_integer(word)=(first+n) mod 4 report "refill order after response" severity failure; n:=n+1; end if;
    wait until falling_edge(clk); wait for 1 ns;
   end loop;
   assert n=0 or n=4 report "refill beat count" severity failure;
  end;
  type shadow_t is array(0 to 16383) of unsigned(31 downto 0); variable shadow:shadow_t;
  variable seed,rand_value:unsigned(31 downto 0):=to_unsigned(947,32); variable a:natural; variable random_write:std_logic; variable phys,virt:unsigned(15 downto 0);
 begin
  for k in 1 to 3 loop wait until falling_edge(clk); end loop; reset<='0'; wait for 1 ns;
  assert safe='1' and bad_safe='0' report "VIPT safety" severity failure;
  access_cache('0',x"000c",x"000c",x"00000000",x"10000003",3,'0');
  access_cache('0',x"0000",x"0000",x"00000000",x"10000000",1,'0');
  access_cache('0',x"0040",x"0040",x"00000000",x"10000010",3,'0');
  access_cache('0',x"0000",x"0000",x"00000000",x"10000000",2,'0');
  access_cache('0',x"0000",x"0000",x"00000000",x"10000000",1,'0');
  access_cache('1',x"1000",x"0000",x"abcdef01",x"abcdef01",1,'0');
  access_cache('0',x"2000",x"0000",x"00000000",x"abcdef01",1,'0');
  access_cache('0',x"0080",x"0080",x"00000000",x"10000020",3,'0');
  access_cache('0',x"0000",x"0000",x"00000000",x"abcdef01",2,'0');
  access_cache('0',x"0040",x"0040",x"00000000",x"10000010",3,'0');
  assert fast=4 and slow=2 and miss=4 and probes=16 report "way counts" severity failure;
  dbg_addr<=x"0000"; wait for 1 ns; assert dbg=x"abcdef01" report "write through" severity failure;
  access_cache('0',x"1004",x"0000",x"00000000",x"00000000",1,'1');
  wait until falling_edge(clk); bad_valid<='1'; wait until falling_edge(clk); bad_valid<='0'; wait for 1 ns;
  assert bad_ready='1' and bad_rv='1' and bad_fault='1' report "unsafe configuration accepted" severity failure;
  for i in 0 to 16383 loop shadow(i):=x"10000000"+to_unsigned(i,32); end loop; shadow(0):=x"abcdef01";
  for i in 0 to 127 loop
   seed:=resize(seed*to_unsigned(1664525,32),32)+to_unsigned(1013904223,32); a:=to_integer(seed(23 downto 10)); random_write:=seed(31);
   seed:=resize(seed*to_unsigned(1664525,32),32)+to_unsigned(1013904223,32); rand_value:=seed;
   phys:=to_unsigned(a*4,16); virt:=seed(31 downto 28)&phys(11 downto 0);
   if random_write='1' then shadow(a):=rand_value; access_cache('1',virt,phys,rand_value,rand_value,0,'0');
   else access_cache('0',virt,phys,x"00000000",shadow(a),0,'0'); end if;
  end loop;
  for i in 0 to 16383 loop dbg_addr<=to_unsigned(i*4,16); wait for 1 ns; assert dbg=shadow(i) report "memory mismatch " & integer'image(i) severity failure; end loop;
  report "TEST PASSED"; finish;
 end process;
 process begin wait for 200 us; assert false report "timeout" severity failure; end process;
end;
