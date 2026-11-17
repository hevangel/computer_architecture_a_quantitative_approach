library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all; use std.env.all;
entity tb_tomasulo_mem_spec_replay is end;
architecture sim of tb_tomasulo_mem_spec_replay is
 type words is array(0 to 2) of std_logic_vector(31 downto 0); type pcs is array(0 to 2) of std_logic_vector(7 downto 0); type nums is array(0 to 2) of unsigned(31 downto 0);
 type rom_t is array(0 to 63) of std_logic_vector(31 downto 0);
 signal clk:std_logic:='0'; signal rst_n,init_we,dinit_we,start:std_logic:='0'; signal init_reg,dbg_reg:natural range 0 to 7:=0; signal dinit_addr,dbg_addr:natural range 0 to 63:=0;
 signal init_data,dinit_data:std_logic_vector(31 downto 0):=(others=>'0'); signal pc:pcs; signal code,regs,mems:words:=(others=>(others=>'0')); signal halted:std_logic_vector(0 to 2);
 signal cycles,commits,branches,flushes,squashed,loads,stores,fwds,replays:nums; signal rom:rom_t:=(others=>x"40000000");
 function ins(op,rd,rs,rt,imm:natural) return std_logic_vector is
 begin return std_logic_vector(to_unsigned(op,4))&std_logic_vector(to_unsigned(rd,4))&std_logic_vector(to_unsigned(rs,4))&std_logic_vector(to_unsigned(rt,4))&std_logic_vector(to_unsigned(imm,16)); end;
begin
 clk<=not clk after 5 ns;
 cores:for g in 0 to 2 generate
  code(g)<=rom(to_integer(unsigned(pc(g)(5 downto 0)))) when not is_x(pc(g)(5 downto 0)) else x"40000000";
  dut:entity work.tomasulo_mem_spec_replay generic map(MUL_LAT=>8,SPEC_MEM=>(g/=0),RESOLVE_BRANCH=>(g/=0),PREDICT_BTFN=>(g=2))
   port map(clk,rst_n,init_we,init_reg,init_data,dinit_we,dinit_addr,dinit_data,start,pc(g),code(g),halted(g),cycles(g),commits(g),branches(g),flushes(g),squashed(g),loads(g),stores(g),fwds(g),replays(g),dbg_reg,regs(g),dbg_addr,mems(g));
 end generate;
 process
  type values8 is array(0 to 7) of unsigned(31 downto 0); type values64 is array(0 to 63) of unsigned(31 downto 0);
  variable gr:values8; variable gm:values64; variable image:rom_t; variable seed:unsigned(31 downto 0):=to_unsigned(8941,32);
  variable ty,rd,rs,rt,imm,op,steps,pcg,ncommit,nbranch,nstore,nload,ntaken,total_replays,addr:integer;
  impure function rnd(limit:positive) return natural is
  begin seed:=resize(seed*to_unsigned(1664525,32),32)+to_unsigned(1013904223,32); return to_integer(seed(30 downto 16)) mod limit; end;
  procedure setup is
  begin
   wait until falling_edge(clk); rst_n<='0'; init_we<='0'; dinit_we<='0'; start<='0'; for k in 1 to 2 loop wait until falling_edge(clk); end loop; rst_n<='1';
   for r in 0 to 7 loop
    wait until falling_edge(clk); init_we<='1'; init_reg<=r;
    case r is when 1 => init_data<=x"00000002"; when 2 => init_data<=x"00000003"; when 5 => init_data<=x"00000037"; when others => init_data<=x"00000000"; end case;
    wait until falling_edge(clk); init_we<='0';
   end loop;
   for a in 0 to 15 loop wait until falling_edge(clk); dinit_we<='1'; dinit_addr<=a; dinit_data<=std_logic_vector(to_unsigned(1000+a,32)); wait until falling_edge(clk); dinit_we<='0'; end loop;
  end;
  procedure run is variable t:natural:=0;
  begin wait until falling_edge(clk); start<='1'; wait until falling_edge(clk); start<='0';
   while halted/="111" and t<1000 loop wait until falling_edge(clk); t:=t+1; end loop;
   assert t<1000 report "timeout" severity failure;
  end;
  procedure check_reg(r:natural; value:std_logic_vector(31 downto 0)) is begin dbg_reg<=r; wait for 1 ns; assert regs(0)=value and regs(1)=value and regs(2)=value report "register " & integer'image(r) severity failure; end;
  procedure check_mem(a:natural; value:std_logic_vector(31 downto 0)) is begin dbg_addr<=a; wait for 1 ns; assert mems(0)=value and mems(1)=value and mems(2)=value report "memory " & integer'image(a) severity failure; end;
 begin
  rom(0)<=ins(2,3,1,2,0); rom(1)<=ins(6,0,3,5,0); rom(2)<=ins(5,4,0,0,9); rom(3)<=ins(4,0,0,0,0);
  setup; run; check_reg(4,x"000003f1"); check_mem(6,x"00000037");
  assert replays(1)=0 and cycles(0)>=cycles(1)+3 report "independent load timing" severity failure;
  report "independent conservative=" & integer'image(to_integer(cycles(0))) & " speculative=" & integer'image(to_integer(cycles(1)));
  rom(2)<=ins(5,4,0,0,6); rom(3)<=ins(0,6,4,4,0); rom(4)<=ins(4,0,0,0,0);
  setup; run; check_reg(4,x"00000037"); check_reg(6,x"0000006e"); check_mem(6,x"00000037");
  assert replays(1)=1 and replays(0)=0 and squashed(1)>=2 report "alias recovery" severity failure;
  rom(0)<=ins(2,3,1,2,0); rom(1)<=ins(3,0,1,0,5); rom(2)<=ins(6,0,0,5,7); rom(3)<=ins(5,6,0,0,7); rom(4)<=ins(0,4,6,6,0); rom(5)<=ins(5,7,0,0,8); rom(6)<=ins(4,0,0,0,0);
  setup; run; check_reg(3,x"00000006"); check_reg(7,x"000003f0"); check_reg(6,x"00000000"); check_mem(7,x"000003ef");
  assert flushes(1)=1 and stores(1)=0 and squashed(1)>0 and cycles(1)<cycles(0) report "branch recovery" severity failure;
  report "branch conservative=" & integer'image(to_integer(cycles(0))) & " resolve=" & integer'image(to_integer(cycles(1)));
  rom(0)<=ins(2,3,1,2,0); rom(1)<=ins(2,6,1,2,0); rom(2)<=ins(6,0,3,5,0); rom(3)<=ins(6,0,6,1,0);
  rom(4)<=ins(5,4,0,0,6); rom(5)<=ins(0,7,4,4,0); rom(6)<=ins(4,0,0,0,0);
  setup; run; check_reg(4,x"00000002"); check_reg(7,x"00000004"); check_mem(6,x"00000002");
  assert replays(1)>0 and stores(1)=2 report "multiple-store recovery" severity failure;
  rom(0)<=ins(2,3,1,2,0); rom(1)<=ins(6,0,3,5,0); rom(2)<=ins(5,4,0,0,6);
  rom(3)<=ins(0,4,1,2,0); rom(4)<=ins(0,6,4,4,0); rom(5)<=ins(4,0,0,0,0);
  setup; run; check_reg(3,x"00000006"); check_reg(4,x"00000005"); check_reg(6,x"0000000a"); check_mem(6,x"00000037");
  assert replays(1)>0 report "WAW recovery" severity failure;
  rom(0)<=ins(1,7,2,1,0); rom(1)<=ins(0,6,6,1,0); rom(2)<=ins(1,2,2,7,0);
  rom(3)<=ins(3,0,2,0,1); rom(4)<=ins(4,0,0,0,0);
  setup; run; check_reg(7,x"00000001"); check_reg(2,x"00000000"); check_reg(6,x"00000006");
  assert branches(1)=3 and flushes(1)=2 and commits(1)=11 and branches(2)=3 and flushes(2)=1 and commits(2)=11 report "ROB wrap branch recovery" severity failure;
  total_replays:=0;
  for pidx in 0 to 99 loop
   image:=(others=>x"40000000");
   for k in 0 to 23 loop
    ty:=rnd(10); rd:=rnd(8); rs:=rnd(8); rt:=rnd(8); imm:=rnd(8); op:=rnd(3);
    if ty<3 then image(k):=ins(op,rd,rs,rt,0);
    elsif ty<6 then image(k):=ins(5,rd,rs,0,imm);
    elsif ty<9 then image(k):=ins(6,0,rs,rt,imm);
    elsif k<22 then image(k):=ins(3,0,rs,0,k+2+(imm mod (23-k)));
    else image(k):=ins(0,rd,rs,rt,0); end if;
   end loop;
   image(24):=ins(4,0,0,0,0); rom<=image;
   gr:=(others=>(others=>'0')); gr(1):=to_unsigned(2,32); gr(2):=to_unsigned(3,32); gr(5):=to_unsigned(55,32);
   for a in 0 to 63 loop if a<16 then gm(a):=to_unsigned(1000+a,32); else gm(a):=(others=>'0'); end if; end loop;
   pcg:=0; steps:=0; ncommit:=0; nbranch:=0; nstore:=0; nload:=0; ntaken:=0;
   while pcg<25 and steps<50 loop
    op:=to_integer(unsigned(image(pcg)(31 downto 28))); rd:=to_integer(unsigned(image(pcg)(26 downto 24)));
    rs:=to_integer(unsigned(image(pcg)(22 downto 20))); rt:=to_integer(unsigned(image(pcg)(18 downto 16))); imm:=to_integer(unsigned(image(pcg)(15 downto 0)));
    ncommit:=ncommit+1; steps:=steps+1;
    case op is
     when 0 => gr(rd):=gr(rs)+gr(rt);
     when 1 => gr(rd):=gr(rs)-gr(rt);
     when 2 => gr(rd):=resize(gr(rs)*gr(rt),32);
     when 3 => nbranch:=nbranch+1; if gr(rs)/=0 then ntaken:=ntaken+1; pcg:=imm-1; end if;
     when 5 => addr:=(to_integer(gr(rs)(5 downto 0))+imm) mod 64; gr(rd):=gm(addr); nload:=nload+1;
     when 6 => addr:=(to_integer(gr(rs)(5 downto 0))+imm) mod 64; gm(addr):=gr(rt); nstore:=nstore+1;
     when others => pcg:=25;
    end case;
    pcg:=pcg+1;
   end loop;
   setup; run;
   for r in 0 to 7 loop check_reg(r,std_logic_vector(gr(r))); end loop;
   for a in 0 to 63 loop check_mem(a,std_logic_vector(gm(a))); end loop;
   assert commits(0)=ncommit and commits(1)=ncommit and branches(0)=nbranch and branches(1)=nbranch and stores(0)=nstore and stores(1)=nstore and loads(0)=nload and loads(1)=nload and flushes(0)=ntaken and flushes(1)>=ntaken and commits(2)=ncommit and branches(2)=nbranch and stores(2)=nstore and loads(2)=nload and flushes(2)>=ntaken report "random counters program " & integer'image(pidx) severity failure;
   if pidx=95 then assert flushes(1)>ntaken and flushes(2)>ntaken report "wrong-path branch recovery accounting" severity failure; end if;
   total_replays:=total_replays+to_integer(replays(1));
  end loop;
  report "random programs=100 speculative replays=" & integer'image(total_replays);
  report "TEST PASSED"; finish;
 end process;
 process begin wait for 400 us; assert false report "timeout" severity failure; end process;
end;
