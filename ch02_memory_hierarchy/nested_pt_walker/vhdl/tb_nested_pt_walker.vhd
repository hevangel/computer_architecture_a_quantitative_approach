library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.env.all;
entity tb_nested_pt_walker is end;
architecture sim of tb_nested_pt_walker is
 signal clk:std_logic:='0'; signal reset:std_logic:='1'; signal invalidate,valid,pwc:std_logic:='0'; signal mem_ready,stall_next:std_logic:='1';
 signal va:unsigned(31 downto 0):=(others=>'0'); signal gr:unsigned(31 downto 0):=x"00010000"; signal hr:unsigned(31 downto 0):=x"00002000";
 signal asid:unsigned(15 downto 0):=(others=>'0'); signal ready,rv,fault,big,mv,mrv:std_logic:='0';
 signal pa,ma,reads,hits,thits,mrdata:unsigned(31 downto 0):=(others=>'0'); signal mode:natural:=0; signal transactions:natural:=0;
 function memory(address:unsigned(31 downto 0); choice:natural) return unsigned is
 begin
  case to_integer(address) is
   when 16#2000# => return x"00004001";
   when 16#2004# => if choice=5 then return x"00401003"; elsif choice=1 then return x"00400003"; else return x"00006001"; end if;
   when 16#4040# => return x"00010001";
   when 16#4048# => return x"00012001";
   when 16#4060# => return x"00018001";
   when 16#4068# => return x"0001a001";
   when 16#4080# => if choice=6 then return x"00020003"; else return x"00020001"; end if;
   when 16#4084# => return x"00021001";
   when 16#4088# => return x"00022001";
   when 16#6048# => return x"00500001";
   when 16#10000# => return x"00012001";
   when 16#12008# => return x"00020001";
   when 16#10008# => if choice=4 then return x"00201003"; elsif choice=1 or choice=2 or choice=5 then return x"00200003"; elsif choice=3 then return x"00000000"; else return x"00012001"; end if;
   when 16#12048# => return x"00020001";
   when 16#1204c# => return x"00021001";
   when 16#18008# => return x"0001a001";
   when 16#1a048# => return x"00021001";
   when others => return x"00000000";
  end case;
 end;
begin
 clk<=not clk after 5 ns;
 dut:entity work.nested_pt_walker port map(clk,reset,invalidate,valid,pwc,va,gr,hr,asid,ready,rv,fault,big,pa,mv,mem_ready,ma,mrv,mrdata,reads,hits,thits);
 process(clk) begin
  if rising_edge(clk) then
   if reset='1' then mrv<='0'; mrdata<=(others=>'0'); transactions<=0;
   else mrv<=mv and mem_ready; if mv='1' and mem_ready='1' then mrdata<=memory(ma,mode); transactions<=transactions+1; end if; end if;
  end if;
 end process;
 process
  procedure clear_cache is begin wait until falling_edge(clk); while ready/='1' loop wait until falling_edge(clk); end loop; invalidate<='1'; wait until falling_edge(clk); invalidate<='0'; end;
  procedure translate(address:unsigned(31 downto 0); id:natural; root:unsigned(31 downto 0); use_pwc,expected_fault:std_logic; expected:unsigned(31 downto 0); superpage:std_logic; read_count:integer) is
   variable before_count,elapsed:natural; variable held_address:unsigned(31 downto 0);
  begin
   wait until falling_edge(clk); while ready/='1' loop wait until falling_edge(clk); end loop;
   va<=address; asid<=to_unsigned(id,16); gr<=root; pwc<=use_pwc; valid<='1'; before_count:=to_integer(reads);
   wait until falling_edge(clk); valid<='0'; wait for 1 ns; elapsed:=1;
   if stall_next='1' then
    while mv/='1' loop wait until falling_edge(clk); wait for 1 ns; end loop;
    held_address:=ma; mem_ready<='0';
    for k in 1 to 3 loop wait until falling_edge(clk); wait for 1 ns; assert mv='1' and ma=held_address and to_integer(reads)=before_count report "memory backpressure" severity failure; end loop;
    mem_ready<='1'; stall_next<='0';
   end if;
   while rv/='1' and elapsed<300 loop wait until falling_edge(clk); wait for 1 ns; elapsed:=elapsed+1; end loop;
   assert rv='1' and fault=expected_fault and (expected_fault='1' or (pa=expected and big=superpage)) and (read_count<0 or to_integer(reads)-before_count=read_count)
    report "translation mismatch at " & integer'image(to_integer(address)) & " reads " & integer'image(to_integer(reads)-before_count) severity failure;
  end;
  variable seed,random_va,random_pa:unsigned(31 downto 0):=to_unsigned(2031,32); variable random_asid:natural;
 begin
  for k in 1 to 3 loop wait until falling_edge(clk); end loop; reset<='0';
  translate(x"00412034",1,x"00010000",'0','0',x"00020034",'0',8);
  translate(x"00412038",1,x"00010000",'0','0',x"00020038",'0',0);
  assert thits=1 and to_integer(reads)=transactions report "TLB counter" severity failure;
  clear_cache;
  translate(x"00412034",1,x"00010000",'1','0',x"00020034",'0',6);
  translate(x"00413034",1,x"00010000",'1','0',x"00021034",'0',2);
  translate(x"00412034",2,x"00018000",'1','0',x"00021034",'0',4);
  translate(x"00412034",1,x"00010000",'1','0',x"00020034",'0',0);
  assert hits>0 report "PWC never hit" severity failure;
  clear_cache; mode<=1;
  translate(x"00412034",1,x"00010000",'0','0',x"00412034",'1',4);
  translate(x"00002034",1,x"00010000",'0','0',x"00020034",'0',8);
  translate(x"00414034",1,x"00010000",'0','0',x"00414034",'1',0);
  translate(x"00002038",1,x"00010000",'0','0',x"00020038",'0',0);
  clear_cache; mode<=2;
  translate(x"00412034",1,x"00010000",'0','0',x"00500034",'0',5);
  translate(x"00413034",1,x"00010000",'0','1',x"00000000",'0',5);
  clear_cache; mode<=3;
  translate(x"00412034",1,x"00010000",'0','1',x"00000000",'0',3);
  translate(x"00412034",1,x"00010001",'0','1',x"00000000",'0',0);
  clear_cache; mode<=4; translate(x"00412034",1,x"00010000",'0','1',x"00000000",'0',3);
  clear_cache; mode<=5; translate(x"00412034",1,x"00010000",'0','1',x"00000000",'0',4);
  clear_cache; mode<=6; translate(x"00412034",1,x"00010000",'0','1',x"00000000",'0',8);
  clear_cache; mode<=0;
  translate(x"00412034",1,x"00010000",'0','0',x"00020034",'0',8);
  translate(x"00412034",2,x"00010000",'0','0',x"00020034",'0',8);
  translate(x"00412034",3,x"00010000",'0','0',x"00020034",'0',8);
  translate(x"00412034",4,x"00010000",'0','0',x"00020034",'0',8);
  translate(x"00412034",1,x"00010000",'0','0',x"00020034",'0',0);
  translate(x"00412034",5,x"00010000",'0','0',x"00020034",'0',8);
  translate(x"00412034",1,x"00010000",'0','0',x"00020034",'0',0);
  translate(x"00412034",2,x"00010000",'0','0',x"00020034",'0',8);
  clear_cache;
  for i in 0 to 127 loop
   seed:=resize(seed*to_unsigned(1664525,32),32)+to_unsigned(1013904223,32);
   if seed(16)='1' then random_va:=x"00413000"; random_pa:=x"00021000";
   else random_va:=x"00412000"; random_pa:=x"00020000"; end if;
   random_va(11 downto 0):=seed(11 downto 0); random_pa(11 downto 0):=seed(11 downto 0);
   random_asid:=1+to_integer(seed(18 downto 17));
   translate(random_va,random_asid,x"00010000",'0','0',random_pa,'0',-1);
  end loop;
  assert to_integer(reads)=transactions report "memory count" severity failure;
  report "TEST PASSED"; finish;
 end process;
 process begin wait for 100 us; assert false report "timeout" severity failure; end process;
end;
