library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity superscalar_dual_issue is
 port(clk,rst_n:in std_logic; imem_addr:out std_logic_vector(31 downto 0); imem_lo,imem_hi:in std_logic_vector(31 downto 0);
      dmem_addr,dmem_wdata:out std_logic_vector(31 downto 0); dmem_we:out std_logic; dmem_rdata:in std_logic_vector(31 downto 0);
      dbg_raddr:in std_logic_vector(4 downto 0); dbg_rdata:out std_logic_vector(31 downto 0); halted:out std_logic;
      stat_cycles,stat_retired,stat_pairs,stat_load_stalls,stat_flushes:out unsigned(31 downto 0));
end;
architecture rtl of superscalar_dual_issue is
 subtype word is std_logic_vector(31 downto 0); subtype regnum is std_logic_vector(4 downto 0);
 constant OP_REG:std_logic_vector(6 downto 0):="0110011";
 constant OP_IMM:std_logic_vector(6 downto 0):="0010011"; constant OP_LUI:std_logic_vector(6 downto 0):="0110111";
 constant OP_LOAD:std_logic_vector(6 downto 0):="0000011"; constant OP_STORE:std_logic_vector(6 downto 0):="0100011";
 constant OP_BRANCH:std_logic_vector(6 downto 0):="1100011"; constant EBREAK:word:=x"00100073";
 type regfile_t is array(1 to 31) of word; type pair_t is array(0 to 1) of word;
 signal regs:regfile_t:=(others=>(others=>'0'));
 signal fetch_pc,id_pc,id0,id1:word:=(others=>'0'); signal id_valid,stop_fetch,halted_i:std_logic:='0';
 signal ei,epc,ea,eb,mi,mr,ms,wi,wvdata,ex_result,ex_store:pair_t:=(others=>(others=>'0'));
 signal ev,mv,wv:std_logic_vector(0 to 1):=(others=>'0');
 signal first_mem,issue_two,load_hazard,redirect:std_logic; signal branch_target:word;
 signal cycles,retired,pairs,load_stalls,flushes:unsigned(31 downto 0):=(others=>'0');
 function is_mem(ins:word) return boolean is begin return ins(6 downto 0)=OP_LOAD or ins(6 downto 0)=OP_STORE; end;
 function is_branch(ins:word) return boolean is begin return ins(6 downto 0)=OP_BRANCH; end;
 function writes_reg(ins:word) return boolean is begin return (ins(6 downto 0)=OP_REG or ins(6 downto 0)=OP_IMM or ins(6 downto 0)=OP_LUI or ins(6 downto 0)=OP_LOAD) and ins(11 downto 7)/="00000"; end;
 function uses1(ins:word) return boolean is begin return ins(6 downto 0)=OP_REG or ins(6 downto 0)=OP_IMM or ins(6 downto 0)=OP_LOAD or ins(6 downto 0)=OP_STORE or ins(6 downto 0)=OP_BRANCH; end;
 function uses2(ins:word) return boolean is begin return ins(6 downto 0)=OP_REG or ins(6 downto 0)=OP_STORE or ins(6 downto 0)=OP_BRANCH; end;
 function depends(ins:word; r:regnum) return boolean is begin return r/="00000" and ((uses1(ins) and ins(19 downto 15)=r) or (uses2(ins) and ins(24 downto 20)=r)); end;
 function forward_ex(r:regnum; original:word; valid_w:std_logic_vector(0 to 1); instr_w,data_w:pair_t; valid_m:std_logic_vector(0 to 1); instr_m,data_m:pair_t) return word is
  variable result:word;
 begin
  if r="00000" then return x"00000000"; end if; result:=original;
  for i in 0 to 1 loop if valid_w(i)='1' and writes_reg(instr_w(i)) and instr_w(i)(11 downto 7)=r then result:=data_w(i); end if; end loop;
  for i in 0 to 1 loop if valid_m(i)='1' and writes_reg(instr_m(i)) and instr_m(i)(6 downto 0)/=OP_LOAD and instr_m(i)(11 downto 7)=r then result:=data_m(i); end if; end loop;
  return result;
 end;
begin
 imem_addr<=fetch_pc; halted<=halted_i; stat_cycles<=cycles; stat_retired<=retired; stat_pairs<=pairs; stat_load_stalls<=load_stalls; stat_flushes<=flushes;
 dbg_rdata<=x"00000000" when dbg_raddr="00000" or is_x(dbg_raddr) else regs(to_integer(unsigned(dbg_raddr)));
 dmem_addr<=mr(1); dmem_wdata<=ms(1); dmem_we<='1' when mv(1)='1' and mi(1)(6 downto 0)=OP_STORE and halted_i='0' else '0';
 process(all)
  variable first_is_mem,second_is_mem,pair_ok,hazard,go:boolean; variable dst,load_rd:regnum;
  variable aa,bb,imm,result:word; variable results,stores:pair_t; variable dest:word;
 begin
  first_is_mem:=is_mem(id0); second_is_mem:=is_mem(id1); dst:=id0(11 downto 7);
  pair_ok:=not is_branch(id0) and id0/=EBREAK and not is_branch(id1) and id1/=EBREAK and not (first_is_mem and second_is_mem) and
    not (writes_reg(id0) and (depends(id1,dst) or (writes_reg(id1) and id1(11 downto 7)=dst)));
  if first_is_mem then first_mem<='1'; else first_mem<='0'; end if;
  if id_valid='1' and pair_ok then issue_two<='1'; else issue_two<='0'; end if;
  load_rd:=(others=>'0'); if ev(1)='1' and ei(1)(6 downto 0)=OP_LOAD then load_rd:=ei(1)(11 downto 7); end if;
  hazard:=id_valid='1' and (depends(id0,load_rd) or (pair_ok and depends(id1,load_rd)));
  if hazard then load_hazard<='1'; else load_hazard<='0'; end if;
  go:=false; dest:=(others=>'0');
  for i in 0 to 1 loop
   aa:=forward_ex(ei(i)(19 downto 15),ea(i),wv,wi,wvdata,mv,mi,mr);
   bb:=forward_ex(ei(i)(24 downto 20),eb(i),wv,wi,wvdata,mv,mi,mr); stores(i):=bb; result:=(others=>'0');
   case ei(i)(6 downto 0) is
    when OP_REG => if ei(i)(30)='1' then result:=std_logic_vector(unsigned(aa)-unsigned(bb)); else result:=std_logic_vector(unsigned(aa)+unsigned(bb)); end if;
    when OP_IMM | OP_LOAD => imm:=std_logic_vector(resize(signed(ei(i)(31 downto 20)),32)); result:=std_logic_vector(unsigned(aa)+unsigned(imm));
    when OP_STORE => imm:=std_logic_vector(resize(signed(std_logic_vector'(ei(i)(31 downto 25)&ei(i)(11 downto 7))),32)); result:=std_logic_vector(unsigned(aa)+unsigned(imm));
    when OP_LUI => result:=ei(i)(31 downto 12)&x"000";
    when others => null;
   end case;
   results(i):=result;
   if i=0 and ev(i)='1' and is_branch(ei(i)) then
    if (ei(i)(14 downto 12)="000" and aa=bb) or (ei(i)(14 downto 12)="001" and aa/=bb) then
     imm:=std_logic_vector(resize(signed(std_logic_vector'(ei(i)(31)&ei(i)(7)&ei(i)(30 downto 25)&ei(i)(11 downto 8)&'0')),32));
     go:=true; dest:=std_logic_vector(unsigned(epc(i))+unsigned(imm));
    end if;
   end if;
  end loop;
  ex_result<=results; ex_store<=stores; branch_target<=dest; if go then redirect<='1'; else redirect<='0'; end if;
 end process;
 process(clk)
  impure function read_id(r:regnum) return word is variable result:word;
  begin
   if r="00000" then return x"00000000"; end if; result:=regs(to_integer(unsigned(r)));
   for i in 0 to 1 loop if wv(i)='1' and writes_reg(wi(i)) and wi(i)(11 downto 7)=r then result:=wvdata(i); end if; end loop;
   return result;
  end;
  variable ins0,ins1:word; variable v0,v1:std_logic; variable retired_now:natural;
 begin
  if rising_edge(clk) then
   if rst_n='0' then
    fetch_pc<=(others=>'0'); id_pc<=(others=>'0'); id0<=(others=>'0'); id1<=(others=>'0'); id_valid<='0'; stop_fetch<='0'; halted_i<='0';
    cycles<=(others=>'0'); retired<=(others=>'0'); pairs<=(others=>'0'); load_stalls<=(others=>'0'); flushes<=(others=>'0'); regs<=(others=>(others=>'0'));
    ev<=(others=>'0'); mv<=(others=>'0'); wv<=(others=>'0'); ei<=(others=>(others=>'0')); mi<=(others=>(others=>'0')); wi<=(others=>(others=>'0'));
    epc<=(others=>(others=>'0')); ea<=(others=>(others=>'0')); eb<=(others=>(others=>'0')); mr<=(others=>(others=>'0')); ms<=(others=>(others=>'0')); wvdata<=(others=>(others=>'0'));
   elsif halted_i='0' then
    retired_now:=0; if wv(0)='1' then retired_now:=retired_now+1; end if; if wv(1)='1' then retired_now:=retired_now+1; end if;
    cycles<=cycles+1; retired<=retired+to_unsigned(retired_now,32);
    for i in 0 to 1 loop
     if wv(i)='1' and writes_reg(wi(i)) then regs(to_integer(unsigned(wi(i)(11 downto 7))))<=wvdata(i); end if;
     wv(i)<=mv(i); wi(i)<=mi(i); if mi(i)(6 downto 0)=OP_LOAD then wvdata(i)<=dmem_rdata; else wvdata(i)<=mr(i); end if;
     mv(i)<=ev(i); mi(i)<=ei(i); mr(i)<=ex_result(i); ms(i)<=ex_store(i); ev(i)<='0';
    end loop;
    if (wv(0)='1' and wi(0)=EBREAK) or (wv(1)='1' and wi(1)=EBREAK) then halted_i<='1'; end if;
    if redirect='1' then fetch_pc<=branch_target; id_valid<='0'; stop_fetch<='0'; flushes<=flushes+1;
    elsif load_hazard='1' and stop_fetch='0' then load_stalls<=load_stalls+1;
    elsif stop_fetch='0' then
     if id_valid='0' then id0<=imem_lo; id1<=imem_hi; id_pc<=fetch_pc; fetch_pc<=std_logic_vector(unsigned(fetch_pc)+8); id_valid<='1';
     else
      v0:='0'; v1:='0'; ins0:=(others=>'0'); ins1:=(others=>'0');
      if first_mem='1' then v1:='1'; ins1:=id0; if issue_two='1' then v0:='1'; ins0:=id1; end if;
      else v0:='1'; ins0:=id0; if issue_two='1' then v1:='1'; ins1:=id1; end if; end if;
      ev(0)<=v0; ev(1)<=v1; ei(0)<=ins0; ei(1)<=ins1;
      if first_mem='1' and issue_two='1' then epc(0)<=std_logic_vector(unsigned(id_pc)+4); else epc(0)<=id_pc; end if;
      if first_mem='1' then epc(1)<=id_pc; else epc(1)<=std_logic_vector(unsigned(id_pc)+4); end if;
      ea(0)<=read_id(ins0(19 downto 15)); eb(0)<=read_id(ins0(24 downto 20)); ea(1)<=read_id(ins1(19 downto 15)); eb(1)<=read_id(ins1(24 downto 20));
      if issue_two='1' then pairs<=pairs+1; id0<=imem_lo; id1<=imem_hi; id_pc<=fetch_pc; fetch_pc<=std_logic_vector(unsigned(fetch_pc)+8);
      elsif id0=EBREAK then id_valid<='0'; stop_fetch<='1';
      else id0<=id1; id1<=imem_lo; id_pc<=std_logic_vector(unsigned(id_pc)+4); fetch_pc<=std_logic_vector(unsigned(fetch_pc)+4); end if;
     end if;
    end if;
   end if;
  end if;
 end process;
end architecture;
