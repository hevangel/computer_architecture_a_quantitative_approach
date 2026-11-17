library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity prf_rename_ooo is
 generic(NPHYS:integer range 9 to 16:=16);
 port(clk,reset,init_we:in std_logic; init_reg:in unsigned(2 downto 0); init_data:in unsigned(31 downto 0);
      issue_valid:in std_logic; issue_op:in unsigned(1 downto 0); issue_dst,issue_src1,issue_src2:in unsigned(2 downto 0); issue_pred_taken:in std_logic; issue_branch_id:in unsigned(7 downto 0);
      issue_ready,recover_valid,recover_taken:out std_logic; recover_branch_id:out unsigned(7 downto 0); idle:out std_logic;
      dbg_reg:in unsigned(2 downto 0); dbg_value:out unsigned(31 downto 0); dbg_front,dbg_arch:out unsigned(3 downto 0);
      dbg_free:out std_logic_vector(15 downto 0); free_count:out unsigned(4 downto 0); rob_count:out unsigned(3 downto 0);
      stat_issued,stat_committed,stat_squashed,stat_recoveries,stat_ooo:out unsigned(31 downto 0));
end;
architecture rtl of prf_rename_ooo is
 constant ADD:natural:=0; constant SUB:natural:=1; constant MUL:natural:=2; constant BR:natural:=3;
 type data16 is array(0 to 15) of unsigned(31 downto 0); type data2 is array(0 to 1) of unsigned(31 downto 0);
 type ids8 is array(0 to 7) of unsigned(7 downto 0); signal branch_id:ids8:=(others=>(others=>'0'));
 type nat8 is array(0 to 7) of natural; type nat2 is array(0 to 1) of natural;
 signal prf:data16:=(others=>(others=>'0')); signal preg_ready,free_bits:std_logic_vector(15 downto 0):=(others=>'0');
 signal front,arch,op,adst,pdst,pold,ps1,ps2:nat8:=(others=>0);
 signal rv,done,executing,pred:std_logic_vector(0 to 7):=(others=>'0'); signal head,tail:natural range 0 to 7:=0; signal count:natural range 0 to 8:=0;
 signal ubusy,udone:std_logic_vector(0 to 1):=(others=>'0'); signal utag,urem:nat2:=(others=>0); signal uvalue:data2:=(others=>(others=>'0'));
 signal has_free,cdb_valid,cdb_unit,recover_now,idle_i,ready_i:std_logic; signal free_pick:natural range 0 to 15; signal cdb_tag:natural range 0 to 7;
 signal cdb_value:unsigned(31 downto 0); signal issued,committed,squashed,recoveries,ooo:unsigned(31 downto 0):=(others=>'0');
 function allowed_mask(n:natural) return std_logic_vector is variable mask:std_logic_vector(15 downto 0):=(others=>'0');
 begin for i in 0 to n-1 loop mask(i):='1'; end loop; return mask; end;
 function distance(tag,h:natural) return natural is begin return (tag+8-h) mod 8; end;
begin
 dbg_value<=prf(arch(to_integer(dbg_reg))); dbg_front<=to_unsigned(front(to_integer(dbg_reg)),4); dbg_arch<=to_unsigned(arch(to_integer(dbg_reg)),4);
 dbg_free<=free_bits; rob_count<=to_unsigned(count,4); stat_issued<=issued; stat_committed<=committed; stat_squashed<=squashed; stat_recoveries<=recoveries; stat_ooo<=ooo;
 idle_i<='1' when count=0 and ubusy="00" else '0'; idle<=idle_i; issue_ready<=ready_i;
 process(all)
  variable has:boolean; variable pick,total,unit_sel,tag_sel:natural; variable value:unsigned(31 downto 0); variable valid,rec:boolean;
 begin
  has:=false; pick:=0; total:=0;
  for p in 0 to 15 loop if free_bits(p)='1' then total:=total+1; if not has then has:=true; pick:=p; end if; end if; end loop;
  if has then has_free<='1'; else has_free<='0'; end if; free_pick<=pick; free_count<=to_unsigned(total,5);
  valid:=udone(0)='1' or udone(1)='1'; if udone(0)='0' and udone(1)='1' then unit_sel:=1; else unit_sel:=0; end if;
  tag_sel:=utag(unit_sel); value:=uvalue(unit_sel); rec:=valid and op(tag_sel)=BR and ((value/=0)/=(pred(tag_sel)='1'));
  if valid then cdb_valid<='1'; else cdb_valid<='0'; end if; if unit_sel=1 then cdb_unit<='1'; else cdb_unit<='0'; end if;
  cdb_tag<=tag_sel; cdb_value<=value; if rec then recover_now<='1'; else recover_now<='0'; end if;
  if count<8 and (to_integer(issue_op)=BR or has) and not rec and recover_valid='0' and reset='0' and init_we='0' then ready_i<='1'; else ready_i<='0'; end if;
 end process;
 process(clk)
  variable pick,tagx,keep,unit_sel,nxt:integer; variable mapx:natural; variable new_free:std_logic_vector(15 downto 0); variable lhs,rhs:unsigned(31 downto 0); variable will_commit,will_issue:boolean;
 begin
  if rising_edge(clk) then
   if reset='1' then
    head<=0; tail<=0; count<=0; free_bits<=allowed_mask(NPHYS) and x"ff00"; preg_ready<=x"00ff"; recover_valid<='0'; recover_taken<='0'; recover_branch_id<=(others=>'0'); branch_id<=(others=>(others=>'0'));
    issued<=(others=>'0'); committed<=(others=>'0'); squashed<=(others=>'0'); recoveries<=(others=>'0'); ooo<=(others=>'0'); prf<=(others=>(others=>'0'));
    for i in 0 to 7 loop front(i)<=i; arch(i)<=i; end loop;
    rv<=(others=>'0'); done<=(others=>'0'); executing<=(others=>'0'); pred<=(others=>'0'); op<=(others=>0); adst<=(others=>0); pdst<=(others=>0); pold<=(others=>0); ps1<=(others=>0); ps2<=(others=>0);
    ubusy<=(others=>'0'); udone<=(others=>'0'); utag<=(others=>0); urem<=(others=>0); uvalue<=(others=>(others=>'0'));
   else
    recover_valid<='0';
    if init_we='1' and idle_i='1' then prf(arch(to_integer(init_reg)))<=init_data; end if;
    if cdb_valid='1' then
     done(cdb_tag)<='1'; if op(cdb_tag)/=BR then prf(pdst(cdb_tag))<=cdb_value; preg_ready(pdst(cdb_tag))<='1'; end if;
     if cdb_tag/=head then ooo<=ooo+1; end if;
     if cdb_unit='1' then unit_sel:=1; else unit_sel:=0; end if; ubusy(unit_sel)<='0'; udone(unit_sel)<='0';
    end if;
    for u in 0 to 1 loop
     if ubusy(u)='0' then
      if recover_now='0' then
       pick:=-1;
       for j in 0 to 7 loop
        if rv(j)='1' and executing(j)='0' and done(j)='0' and ((op(j)=MUL)=(u=1)) and preg_ready(ps1(j))='1' and (op(j)=BR or preg_ready(ps2(j))='1') then
         if pick<0 then pick:=j; elsif distance(j,head)<distance(pick,head) then pick:=j; end if;
        end if;
       end loop;
       if pick>=0 then
        lhs:=prf(ps1(pick)); rhs:=prf(ps2(pick)); ubusy(u)<='1'; udone(u)<='0'; utag(u)<=pick; executing(pick)<='1';
        if u=0 then urem(u)<=2; else urem(u)<=4; end if;
        case op(pick) is
         when ADD => uvalue(u)<=lhs+rhs; when SUB => uvalue(u)<=lhs-rhs; when MUL => uvalue(u)<=resize(lhs*rhs,32);
         when others => if lhs/=0 then uvalue(u)<=to_unsigned(1,32); else uvalue(u)<=(others=>'0'); end if;
        end case;
       end if;
      end if;
     elsif udone(u)='0' then if urem(u)=1 then urem(u)<=0; udone(u)<='1'; else urem(u)<=urem(u)-1; end if; end if;
    end loop;
    will_commit:=count/=0 and done(head)='1' and recover_now='0'; will_issue:=issue_valid='1' and ready_i='1';
    if will_commit then
     if op(head)/=BR then arch(adst(head))<=pdst(head); free_bits(pold(head))<='1'; end if;
     rv(head)<='0'; head<=(head+1) mod 8; committed<=committed+1;
    end if;
    if will_issue then
     rv(tail)<='1'; done(tail)<='0'; executing(tail)<='0'; op(tail)<=to_integer(issue_op); pred(tail)<=issue_pred_taken; branch_id(tail)<=issue_branch_id;
     ps1(tail)<=front(to_integer(issue_src1)); ps2(tail)<=front(to_integer(issue_src2)); adst(tail)<=to_integer(issue_dst);
     if to_integer(issue_op)/=BR then pdst(tail)<=free_pick; pold(tail)<=front(to_integer(issue_dst)); front(to_integer(issue_dst))<=free_pick; free_bits(free_pick)<='0'; preg_ready(free_pick)<='0'; end if;
     tail<=(tail+1) mod 8; issued<=issued+1;
    end if;
    nxt:=count; if will_issue then nxt:=nxt+1; end if; if will_commit then nxt:=nxt-1; end if; count<=nxt;
    if recover_now='1' then
     keep:=distance(cdb_tag,head)+1; recover_valid<='1'; recover_branch_id<=branch_id(cdb_tag); if cdb_value/=0 then recover_taken<='1'; else recover_taken<='0'; end if;
     recoveries<=recoveries+1; squashed<=squashed+to_unsigned(count-keep,32); tail<=(head+keep) mod 8; count<=keep;
     new_free:=allowed_mask(NPHYS); for r in 0 to 7 loop new_free(arch(r)):='0'; end loop;
     for off in 0 to 7 loop if off<keep then tagx:=(head+off) mod 8; if rv(tagx)='1' and op(tagx)/=BR then new_free(pdst(tagx)):='0'; end if; end if; end loop;
     free_bits<=new_free;
     for r in 0 to 7 loop
      mapx:=arch(r); for off in 0 to 7 loop if off<keep then tagx:=(head+off) mod 8; if rv(tagx)='1' and op(tagx)/=BR and adst(tagx)=r then mapx:=pdst(tagx); end if; end if; end loop;
      front(r)<=mapx;
     end loop;
     for j in 0 to 7 loop if rv(j)='1' and distance(j,head)>=keep and distance(j,head)<count then rv(j)<='0'; done(j)<='0'; executing(j)<='0'; end if; end loop;
     for u in 0 to 1 loop if ubusy(u)='1' and distance(utag(u),head)>=keep then ubusy(u)<='0'; udone(u)<='0'; end if; end loop;
    end if;
   end if;
  end if;
 end process;
end architecture;
