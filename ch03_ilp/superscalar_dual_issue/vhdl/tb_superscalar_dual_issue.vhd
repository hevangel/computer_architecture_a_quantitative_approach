library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.env.all;
entity tb_superscalar_dual_issue is end;
architecture sim of tb_superscalar_dual_issue is
 subtype word is std_logic_vector(31 downto 0); type rom_t is array(0 to 255) of word; type mem_t is array(0 to 63) of word;
 signal clk:std_logic:='0'; signal rst_n:std_logic:='0'; signal mode:natural range 0 to 3:=0;
 signal ia0,lo,hi,da0,dw0,dr0,dbg0,ia1,ins1,da1,dw1,dr1,dbg1:word:=(others=>'0');
 signal we0,h0,we1,h1:std_logic; signal dbg_addr:std_logic_vector(4 downto 0):=(others=>'0');
 signal cyc0,ret0,pairs,stalls,flushes,cyc1,ret1,stall1,flush1:unsigned(31 downto 0);
 signal mem0,mem1:mem_t:=(others=>(others=>'0'));
 function addi(rd,rs,imm:integer) return word is begin return std_logic_vector(to_signed(imm,12))&std_logic_vector(to_unsigned(rs,5))&"000"&std_logic_vector(to_unsigned(rd,5))&"0010011"; end;
 function add(rd,rs1,rs2:integer) return word is begin return "0000000"&std_logic_vector(to_unsigned(rs2,5))&std_logic_vector(to_unsigned(rs1,5))&"000"&std_logic_vector(to_unsigned(rd,5))&"0110011"; end;
 function sub(rd,rs1,rs2:integer) return word is begin return "0100000"&std_logic_vector(to_unsigned(rs2,5))&std_logic_vector(to_unsigned(rs1,5))&"000"&std_logic_vector(to_unsigned(rd,5))&"0110011"; end;
 function lw(rd,offset:integer) return word is begin return std_logic_vector(to_signed(offset,12))&"00000"&"010"&std_logic_vector(to_unsigned(rd,5))&"0000011"; end;
 function sw(rs,offset:integer) return word is variable i:std_logic_vector(11 downto 0); begin i:=std_logic_vector(to_signed(offset,12)); return i(11 downto 5)&std_logic_vector(to_unsigned(rs,5))&"00000"&"010"&i(4 downto 0)&"0100011"; end;
 function beq(r1,r2,offset:integer) return word is variable i:std_logic_vector(12 downto 0); begin i:=std_logic_vector(to_signed(offset,13)); return i(12)&i(10 downto 5)&std_logic_vector(to_unsigned(r2,5))&std_logic_vector(to_unsigned(r1,5))&"000"&i(4 downto 1)&i(11)&"1100011"; end;
 function bne(r1,r2,offset:integer) return word is variable i:std_logic_vector(12 downto 0); begin i:=std_logic_vector(to_signed(offset,13)); return i(12)&i(10 downto 5)&std_logic_vector(to_unsigned(r2,5))&std_logic_vector(to_unsigned(r1,5))&"001"&i(4 downto 1)&i(11)&"1100011"; end;
 function program(which:natural) return rom_t is variable m:rom_t:=(others=>x"00100073"); variable k:natural:=0;
  variable seed:unsigned(31 downto 0):=to_unsigned(731,32); variable op,rd,rs1,rs2,imm,addr:integer;
 begin
  if which=0 then
   m(0):=addi(1,0,5); m(1):=addi(2,0,7); m(2):=add(3,1,2); m(3):=addi(4,3,1);
   m(4):=sw(4,64); m(5):=lw(5,64); m(6):=add(6,5,3); m(7):=beq(6,6,16);
   m(8):=addi(7,0,99); m(9):=sw(4,76); m(10):=x"00100073";
   m(11):=addi(8,0,3); m(12):=addi(9,0,1); m(13):=addi(9,9,2);
   m(14):=addi(10,9,5); m(15):=sw(10,68); m(16):=addi(11,0,3); m(17):=addi(12,0,0);
   m(18):=addi(12,12,1); m(19):=addi(11,11,-1); m(20):=bne(11,0,-8); m(21):=sw(12,72); m(22):=x"00100073";
  elsif which=3 then
   for i in 0 to 179 loop
    seed:=resize(seed*to_unsigned(1664525,32),32)+to_unsigned(1013904223,32);
    op:=to_integer(seed(31 downto 30)); rd:=1+to_integer(seed(7 downto 4)); rs1:=to_integer(seed(3 downto 0)); rs2:=to_integer(seed(11 downto 8)); imm:=to_integer(seed(20 downto 16))-16; addr:=(8+to_integer(seed(12 downto 10)))*4;
    case op is
     when 0 => m(i):=addi(rd,rs1,imm);
     when 1 => if seed(29)='1' then m(i):=sub(rd,rs1,rs2); else m(i):=add(rd,rs1,rs2); end if;
     when 2 => m(i):=lw(rd,addr);
     when others => m(i):=sw(rs2,addr);
    end case;
   end loop; m(180):=x"00100073";
  else
   for i in 0 to 22 loop
    if which=1 then
     m(k):=lw(5,(i mod 8)*4); k:=k+1; m(k):=addi(1,1,1); k:=k+1;
     m(k):=addi(3,3,1); k:=k+1; m(k):=lw(6,((i+1) mod 8)*4); k:=k+1;
     m(k):=add(2,2,5); k:=k+1; m(k):=addi(4,4,1); k:=k+1;
     m(k):=sub(2,2,6); k:=k+1; m(k):=addi(7,7,1); k:=k+1;
    else
     m(k):=lw(5,(i mod 8)*4); k:=k+1; m(k):=add(2,2,5); k:=k+1;
     m(k):=addi(1,1,1); k:=k+1; m(k):=addi(3,3,1); k:=k+1;
     m(k):=lw(6,((i+1) mod 8)*4); k:=k+1; m(k):=sub(2,2,6); k:=k+1;
     m(k):=addi(4,4,1); k:=k+1; m(k):=addi(7,7,1); k:=k+1;
    end if;
   end loop;
   m(k):=sw(2,64); m(k+1):=x"00100073";
  end if; return m;
 end;
 constant rom0:rom_t:=program(0); constant rom1:rom_t:=program(1); constant rom2:rom_t:=program(2); constant rom3:rom_t:=program(3);
 function instruction(addr:word; which:natural) return word is variable index:natural;
 begin
  if is_x(addr) or unsigned(addr)>=1024 then return x"00100073"; end if;
  index:=to_integer(unsigned(addr(9 downto 2))); if which=0 then return rom0(index); elsif which=1 then return rom1(index); elsif which=2 then return rom2(index); else return rom3(index); end if;
 end;
begin
 clk<=not clk after 5 ns;
 dut:entity work.superscalar_dual_issue port map(clk,rst_n,ia0,lo,hi,da0,dw0,we0,dr0,dbg_addr,dbg0,h0,cyc0,ret0,pairs,stalls,flushes);
 scalar:entity work.rv32i_pipeline port map(clk,rst_n,ia1,ins1,da1,dw1,we1,dr1,dbg_addr,dbg1,h1,cyc1,ret1,stall1,flush1);
 lo<=instruction(ia0,mode); hi<=instruction(std_logic_vector(unsigned(ia0)+4),mode); ins1<=instruction(ia1,mode);
 dr0<=mem0(to_integer(unsigned(da0(7 downto 2)))) when not is_x(da0(7 downto 2)) else (others=>'0');
 dr1<=mem1(to_integer(unsigned(da1(7 downto 2)))) when not is_x(da1(7 downto 2)) else (others=>'0');
 process(clk) begin if rising_edge(clk) then
  if rst_n='0' then
   for i in 0 to 63 loop if i<8 then mem0(i)<=std_logic_vector(to_unsigned((i+1)*(i+1),32)); mem1(i)<=std_logic_vector(to_unsigned((i+1)*(i+1),32)); else mem0(i)<=(others=>'0'); mem1(i)<=(others=>'0'); end if; end loop;
  else
   if we0='1' then mem0(to_integer(unsigned(da0(7 downto 2))))<=dw0; end if;
   if we1='1' then mem1(to_integer(unsigned(da1(7 downto 2))))<=dw1; end if;
  end if;
 end if; end process;
 process
  procedure execute_case(expect_hazards:boolean) is variable t:natural:=0;
  begin
   for i in 1 to 3 loop wait until falling_edge(clk); end loop; rst_n<='1';
   while not (h0='1' and h1='1') and t<3000 loop wait until falling_edge(clk); t:=t+1; end loop;
   assert t<3000 report "timeout" severity failure;
   for i in 0 to 31 loop dbg_addr<=std_logic_vector(to_unsigned(i,5)); wait for 1 ns; assert dbg0=dbg1 report "register mismatch x" & integer'image(i) severity failure; end loop;
   for i in 0 to 63 loop assert mem0(i)=mem1(i) report "memory mismatch " & integer'image(i) severity failure; end loop;
   assert ret0=ret1 report "retired mismatch" severity failure;
   if expect_hazards then assert stalls>0 and flushes>0 and pairs>0 report "missing hazard events" severity failure; end if;
  end;
  variable scheduled_cycles,unscheduled_cycles:natural; type saved_regs_t is array(0 to 31) of word; variable saved_regs:saved_regs_t; variable saved_mem:mem_t;
 begin
  execute_case(true); dbg_addr<=std_logic_vector(to_unsigned(7,5)); wait for 1 ns; assert dbg0=x"00000000" and mem0(16)=x"0000000d" and mem0(17)=x"00000008" and mem0(18)=x"00000003" and mem0(19)=x"00000000" report "directed outcome" severity failure;
  wait until falling_edge(clk); rst_n<='0'; mode<=1; execute_case(false); scheduled_cycles:=to_integer(cyc0);
  assert mem0(16)=x"ffffffc1" and to_integer(ret0)*2>to_integer(cyc0)*3 report "scheduled result or IPC" severity failure;
  for i in 0 to 31 loop dbg_addr<=std_logic_vector(to_unsigned(i,5)); wait for 1 ns; saved_regs(i):=dbg0; end loop;
  for i in 0 to 63 loop saved_mem(i):=mem0(i); end loop;
  wait until falling_edge(clk); rst_n<='0'; mode<=2; execute_case(false); unscheduled_cycles:=to_integer(cyc0);
  assert mem0(16)=x"ffffffc1" and scheduled_cycles<unscheduled_cycles report "schedule comparison" severity failure;
  for i in 0 to 31 loop dbg_addr<=std_logic_vector(to_unsigned(i,5)); wait for 1 ns; assert dbg0=saved_regs(i) report "schedule register mismatch" severity failure; end loop;
  for i in 0 to 63 loop assert mem0(i)=saved_mem(i) report "schedule memory mismatch" severity failure; end loop;
  wait until falling_edge(clk); rst_n<='0'; mode<=3; execute_case(false);
  report "scheduled " & integer'image(scheduled_cycles) & " cycles; unscheduled " & integer'image(unscheduled_cycles) & " cycles";
  report "TEST PASSED"; finish;
 end process;
 process begin wait for 100 us; assert false report "timeout" severity failure; end process;
end;
