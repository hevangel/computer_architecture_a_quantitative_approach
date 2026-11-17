library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity directory_limited_evict is
 generic(MODE:natural:=0);
 port(clk,reset,req_valid:in std_logic; req_node:in unsigned(2 downto 0); req_write:in std_logic;
      req_block:in unsigned(1 downto 0); req_data:in unsigned(31 downto 0);
      resp_valid:out std_logic; resp_data,stat_inv,stat_puts,stat_putm,stat_fetch:out unsigned(31 downto 0);
      dbg_node:in unsigned(2 downto 0); dbg_block:in unsigned(1 downto 0);
      dbg_cache_state,dbg_directory_state,dbg_cached_block:out unsigned(1 downto 0);
      dbg_cache_data,dbg_memory:out unsigned(31 downto 0); dbg_targets:out std_logic_vector(7 downto 0));
end entity;
architecture rtl of directory_limited_evict is
 constant I:unsigned(1 downto 0):="00"; constant S:unsigned(1 downto 0):="01"; constant M:unsigned(1 downto 0):="10";
 type state8 is array(0 to 7) of unsigned(1 downto 0); type state4 is array(0 to 3) of unsigned(1 downto 0);
 type data8 is array(0 to 7) of unsigned(31 downto 0); type data4 is array(0 to 3) of unsigned(31 downto 0);
 type ptr4 is array(0 to 3) of unsigned(2 downto 0); type count4 is array(0 to 3) of natural range 0 to 2;
 type full4 is array(0 to 3) of std_logic_vector(7 downto 0); type coarse4 is array(0 to 3) of std_logic_vector(3 downto 0);
 signal cs,cb:state8:=(others=>I); signal ds:state4:=(others=>I); signal cd:data8:=(others=>(others=>'0'));
 signal memory:data4:=(others=>(others=>'0')); signal owner,ptr0,ptr1:ptr4:=(others=>(others=>'0'));
 signal pcount:count4:=(others=>0); signal overflow:std_logic_vector(0 to 3):=(others=>'0');
 signal full:full4:=(others=>(others=>'0')); signal coarse:coarse4:=(others=>(others=>'0'));
 signal inv,puts,putm,fetches:unsigned(31 downto 0):=(others=>'0');
 impure function targets(b:natural) return std_logic_vector is
  variable mask:std_logic_vector(7 downto 0):=(others=>'0');
 begin
  if MODE=0 then mask:=full(b);
  elsif MODE=1 then
   if overflow(b)='1' then mask:=(others=>'1');
   else
    if pcount(b)>0 then mask(to_integer(ptr0(b))):='1'; end if;
    if pcount(b)>1 then mask(to_integer(ptr1(b))):='1'; end if;
   end if;
  else for k in 0 to 7 loop if coarse(b)(k/2)='1' then mask(k):='1'; end if; end loop; end if;
  return mask;
 end;
begin
 assert MODE<=2 report "unsupported directory mode" severity failure;
 stat_inv<=inv; stat_puts<=puts; stat_putm<=putm; stat_fetch<=fetches;
 dbg_cache_state<=cs(to_integer(dbg_node)); dbg_cached_block<=cb(to_integer(dbg_node)); dbg_cache_data<=cd(to_integer(dbg_node));
 dbg_directory_state<=ds(to_integer(dbg_block)); dbg_memory<=memory(to_integer(dbg_block));
 process(dbg_block,full,pcount,ptr0,ptr1,overflow,coarse) begin dbg_targets<=targets(to_integer(dbg_block)); end process;
 process(clk)
  variable n,b,v,oldowner,count:integer; variable mask:std_logic_vector(7 downto 0); variable groups:std_logic_vector(3 downto 0);
 begin
  if rising_edge(clk) then
   if reset='1' then
    resp_valid<='0'; resp_data<=(others=>'0'); inv<=(others=>'0'); puts<=(others=>'0'); putm<=(others=>'0'); fetches<=(others=>'0');
    cs<=(others=>I); cb<=(others=>I); cd<=(others=>(others=>'0'));
    ds<=(others=>I); owner<=(others=>(others=>'0')); ptr0<=(others=>(others=>'0')); ptr1<=(others=>(others=>'0'));
    pcount<=(others=>0); overflow<=(others=>'0'); full<=(others=>(others=>'0')); coarse<=(others=>(others=>'0'));
    for i in 0 to 3 loop memory(i)<=to_unsigned(160+i,32); end loop;
   else
    resp_valid<='0';
    if req_valid='1' then
     n:=to_integer(req_node); b:=to_integer(req_block); resp_valid<='1';
     if cs(n)/=I and cb(n)=req_block and (req_write='0' or cs(n)=M) then
      if req_write='1' then cd(n)<=req_data; resp_data<=req_data; else resp_data<=cd(n); end if;
     else
      if cs(n)/=I and cb(n)/=req_block then
       v:=to_integer(cb(n));
       if cs(n)=M then
        memory(v)<=cd(n); ds(v)<=I; putm<=putm+1; full(v)<=(others=>'0'); pcount(v)<=0; overflow(v)<='0'; coarse(v)<=(others=>'0');
       else
        puts<=puts+1;
        if MODE=0 then
         mask:=full(v); mask(n):='0'; full(v)<=mask; if mask=x"00" then ds(v)<=I; end if;
        elsif MODE=1 and overflow(v)='0' then
         if pcount(v)=1 and ptr0(v)=req_node then pcount(v)<=0; ds(v)<=I;
         elsif pcount(v)=2 and ptr0(v)=req_node then ptr0(v)<=ptr1(v); pcount(v)<=1;
         elsif pcount(v)=2 and ptr1(v)=req_node then pcount(v)<=1; end if;
        end if;
       end if;
      end if;
      if req_write='0' then
       if ds(b)=M then
        oldowner:=to_integer(owner(b)); memory(b)<=cd(oldowner); cd(n)<=cd(oldowner); resp_data<=cd(oldowner);
        cs(oldowner)<=S; fetches<=fetches+1; ds(b)<=S;
        if MODE=0 then
         mask:=(others=>'0'); mask(oldowner):='1'; mask(n):='1'; full(b)<=mask;
        elsif MODE=1 then ptr0(b)<=to_unsigned(oldowner,3); ptr1(b)<=req_node; pcount(b)<=2; overflow(b)<='0';
        else groups:=(others=>'0'); groups(oldowner/2):='1'; groups(n/2):='1'; coarse(b)<=groups; end if;
       else
        cd(n)<=memory(b); resp_data<=memory(b); ds(b)<=S;
        if MODE=0 then mask:=full(b); mask(n):='1'; full(b)<=mask;
        elsif MODE=1 and overflow(b)='0' then
         if pcount(b)=0 then ptr0(b)<=req_node; pcount(b)<=1;
         elsif ptr0(b)/=req_node and (pcount(b)=1 or ptr1(b)/=req_node) then
          if pcount(b)=1 then ptr1(b)<=req_node; pcount(b)<=2; else overflow(b)<='1'; end if;
         end if;
        elsif MODE=2 then groups:=coarse(b); groups(n/2):='1'; coarse(b)<=groups; end if;
       end if;
       cs(n)<=S; cb(n)<=req_block;
      else
       if ds(b)=M then
        oldowner:=to_integer(owner(b)); memory(b)<=cd(oldowner); cs(oldowner)<=I; fetches<=fetches+1;
       elsif ds(b)=S then
        mask:=targets(b); mask(n):='0'; count:=0;
        for k in 0 to 7 loop
         if mask(k)='1' then
          count:=count+1; if cs(k)/=I and cb(k)=req_block then cs(k)<=I; end if;
         end if;
        end loop;
        inv<=inv+to_unsigned(count,32);
       end if;
       cs(n)<=M; cb(n)<=req_block; cd(n)<=req_data; resp_data<=req_data; ds(b)<=M; owner(b)<=req_node;
       full(b)<=(others=>'0'); pcount(b)<=0; overflow(b)<='0'; coarse(b)<=(others=>'0');
      end if;
     end if;
    end if;
   end if;
  end if;
 end process;
end architecture;
