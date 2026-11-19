library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity nested_pt_walker is
 port(clk,reset,invalidate,req_valid,pwc_enable:in std_logic;
      req_vaddr,req_guest_root,req_host_root:in unsigned(31 downto 0); req_asid:in unsigned(15 downto 0);
      req_ready,resp_valid,resp_fault,resp_super:out std_logic; resp_paddr:out unsigned(31 downto 0);
      mem_valid:out std_logic; mem_ready:in std_logic; mem_addr:out unsigned(31 downto 0);
      mem_rvalid:in std_logic; mem_rdata:in unsigned(31 downto 0);
      stat_mem_reads,stat_pwc_hits,stat_tlb_hits:out unsigned(31 downto 0));
end;
architecture rtl of nested_pt_walker is
 type state_t is (IDLE,HOST_START,LOOKUP,SEND,WAIT_DATA,HOST_ROOT,HOST_LEAF,GUEST_ENTRY);
 type ctx_t is (GROOT,GLEAF,DATA); signal state,return_state:state_t:=IDLE; signal ctx:ctx_t:=GROOT;
 type bit16 is array(0 to 15) of std_logic; type words16 is array(0 to 15) of unsigned(31 downto 0);
 type bit4 is array(0 to 3) of std_logic; type words4 is array(0 to 3) of unsigned(31 downto 0);
 type asids4 is array(0 to 3) of unsigned(15 downto 0); type ages4 is array(0 to 3) of natural range 0 to 3;
 signal pv:bit16:=(others=>'0'); signal paddr,pdata:words16:=(others=>(others=>'0')); signal pnext:natural range 0 to 15:=0;
 signal tv,tsuper:bit4:=(others=>'0'); signal tasid:asids4:=(others=>(others=>'0')); signal tvpn,tppn,tgr,thr:words4:=(others=>(others=>'0')); signal tage:ages4:=(others=>0);
 signal va_q,groot_q,hroot_q,gpa_q,pte_addr,pte_word:unsigned(31 downto 0):=(others=>'0'); signal asid_q:unsigned(15 downto 0):=(others=>'0');
 signal guest_super,pwc_q:std_logic:='0'; signal tlb_hit,pwc_hit:std_logic; signal thit:natural range 0 to 3; signal phit:natural range 0 to 15;
 signal reads,pwc_hits,tlb_hits:unsigned(31 downto 0):=(others=>'0');
begin
 req_ready<='1' when state=IDLE and invalidate='0' else '0'; mem_valid<='1' when state=SEND else '0'; mem_addr<=pte_addr;
 stat_mem_reads<=reads; stat_pwc_hits<=pwc_hits; stat_tlb_hits<=tlb_hits;
 process(all)
  variable tf,pf:std_logic; variable ti:natural range 0 to 3; variable pi:natural range 0 to 15;
 begin
  tf:='0'; pf:='0'; ti:=0; pi:=0;
  for i in 0 to 3 loop
   if tv(i)='1' and tasid(i)=req_asid and tgr(i)=req_guest_root and thr(i)=req_host_root and
      ((tsuper(i)='1' and tvpn(i)=shift_right(req_vaddr,21)) or (tsuper(i)='0' and tvpn(i)=shift_right(req_vaddr,12))) then tf:='1'; ti:=i; end if;
  end loop;
  for i in 0 to 15 loop if pv(i)='1' and paddr(i)=pte_addr then pf:='1'; pi:=i; end if; end loop;
  tlb_hit<=tf; thit<=ti; pwc_hit<=pf; phit<=pi;
 end process;
 process(clk)
  procedure finish_host(phys:unsigned(31 downto 0); host_super:std_logic) is
   variable victim,oldest:natural range 0 to 3; variable big:std_logic;
  begin
   if ctx=DATA then
    big:=guest_super and host_super; resp_valid<='1'; resp_fault<='0'; resp_paddr<=phys; resp_super<=big;
    victim:=0; oldest:=tage(0);
    for i in 0 to 3 loop if tv(i)='0' then victim:=i; end if; end loop;
    if tv(0)='1' and tv(1)='1' and tv(2)='1' and tv(3)='1' then
     victim:=0; oldest:=tage(0); for i in 1 to 3 loop if tage(i)>oldest then oldest:=tage(i); victim:=i; end if; end loop;
    end if;
    for i in 0 to 3 loop if i/=victim and tv(i)='1' and tage(i)/=3 then tage(i)<=tage(i)+1; end if; end loop;
    tv(victim)<='1'; tsuper(victim)<=big; tasid(victim)<=asid_q; tgr(victim)<=groot_q; thr(victim)<=hroot_q;
    if big='1' then tvpn(victim)<=shift_right(va_q,21); tppn(victim)<=shift_right(phys,21);
    else tvpn(victim)<=shift_right(va_q,12); tppn(victim)<=shift_right(phys,12); end if;
    tage(victim)<=0; state<=IDLE;
   else pte_addr<=phys; return_state<=GUEST_ENTRY; state<=LOOKUP; end if;
  end procedure;
 begin
  if rising_edge(clk) then
   if reset='1' then
    state<=IDLE; resp_valid<='0'; resp_fault<='0'; resp_super<='0'; resp_paddr<=(others=>'0');
    reads<=(others=>'0'); pwc_hits<=(others=>'0'); tlb_hits<=(others=>'0'); pnext<=0;
    pv<=(others=>'0'); paddr<=(others=>(others=>'0')); pdata<=(others=>(others=>'0'));
    tv<=(others=>'0'); tsuper<=(others=>'0'); tasid<=(others=>(others=>'0')); tvpn<=(others=>(others=>'0')); tppn<=(others=>(others=>'0'));
    tgr<=(others=>(others=>'0')); thr<=(others=>(others=>'0')); tage<=(others=>0);
   else
    resp_valid<='0'; resp_fault<='0';
    if state=IDLE and invalidate='1' then pv<=(others=>'0'); tv<=(others=>'0'); pnext<=0;
    else case state is
     when IDLE => if req_valid='1' then
      if req_guest_root(12 downto 0)/=to_unsigned(0,13) or req_host_root(12 downto 0)/=to_unsigned(0,13) then
       resp_valid<='1'; resp_fault<='1'; resp_paddr<=(others=>'0'); resp_super<='0';
      elsif tlb_hit='1' then
       resp_valid<='1'; resp_super<=tsuper(thit); tlb_hits<=tlb_hits+1;
       if tsuper(thit)='1' then resp_paddr<=tppn(thit)(10 downto 0)&req_vaddr(20 downto 0);
       else resp_paddr<=tppn(thit)(19 downto 0)&req_vaddr(11 downto 0); end if;
       for i in 0 to 3 loop if tv(i)='1' and tage(i)<tage(thit) then tage(i)<=tage(i)+1; end if; end loop; tage(thit)<=0;
      else
       va_q<=req_vaddr; asid_q<=req_asid; groot_q<=req_guest_root; hroot_q<=req_host_root; pwc_q<=pwc_enable;
       gpa_q<=req_guest_root+shift_left(resize(req_vaddr(31 downto 21),32),2); guest_super<='0'; ctx<=GROOT; state<=HOST_START;
      end if;
     end if;
     when HOST_START => pte_addr<=hroot_q+shift_left(resize(gpa_q(31 downto 21),32),2); return_state<=HOST_ROOT; state<=LOOKUP;
     when LOOKUP => if pwc_q='1' and pwc_hit='1' then pte_word<=pdata(phit); pwc_hits<=pwc_hits+1; state<=return_state; else state<=SEND; end if;
     when SEND => if mem_ready='1' then reads<=reads+1; state<=WAIT_DATA; end if;
     when WAIT_DATA => if mem_rvalid='1' then
      pte_word<=mem_rdata; if pwc_q='1' then pv(pnext)<='1'; paddr(pnext)<=pte_addr; pdata(pnext)<=mem_rdata; pnext<=(pnext+1) mod 16; end if; state<=return_state;
     end if;
     when HOST_ROOT =>
      if pte_word(0)='0' or (pte_word(1)='1' and pte_word(20 downto 12)/=to_unsigned(0,9)) then
       resp_valid<='1'; resp_fault<='1'; resp_paddr<=(others=>'0'); resp_super<='0'; state<=IDLE;
      elsif pte_word(1)='1' then finish_host(pte_word(31 downto 21)&gpa_q(20 downto 0),'1');
      else pte_addr<=(pte_word(31 downto 12)&x"000")+shift_left(resize(gpa_q(20 downto 12),32),2); return_state<=HOST_LEAF; state<=LOOKUP; end if;
     when HOST_LEAF =>
      if pte_word(0)='0' or pte_word(1)='1' then resp_valid<='1'; resp_fault<='1'; resp_paddr<=(others=>'0'); resp_super<='0'; state<=IDLE;
      else finish_host(pte_word(31 downto 12)&gpa_q(11 downto 0),'0'); end if;
     when GUEST_ENTRY =>
      if pte_word(0)='0' or (ctx=GLEAF and pte_word(1)='1') or (ctx=GROOT and pte_word(1)='1' and pte_word(20 downto 12)/=to_unsigned(0,9)) then
       resp_valid<='1'; resp_fault<='1'; resp_paddr<=(others=>'0'); resp_super<='0'; state<=IDLE;
      elsif ctx=GROOT and pte_word(1)='0' then
       gpa_q<=(pte_word(31 downto 12)&x"000")+shift_left(resize(va_q(20 downto 12),32),2); ctx<=GLEAF; state<=HOST_START;
      else
       if ctx=GROOT then gpa_q<=pte_word(31 downto 21)&va_q(20 downto 0); guest_super<='1';
       else gpa_q<=pte_word(31 downto 12)&va_q(11 downto 0); guest_super<='0'; end if;
       ctx<=DATA; state<=HOST_START;
      end if;
    end case; end if;
   end if;
  end if;
 end process;
end architecture;
