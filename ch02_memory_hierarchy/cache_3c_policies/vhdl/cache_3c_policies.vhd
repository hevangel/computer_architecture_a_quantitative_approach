-- Finite 8-bit block-address cache policy evaluator and fully-associative 3C shadow.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity cache_3c_policies is
 generic(SETS:positive:=4; ASSOC:positive:=1; POLICY:natural:=0);
 port(clk,reset,valid:in std_logic; block_addr:in unsigned(7 downto 0);
      hit:out std_logic; miss_kind:out unsigned(1 downto 0);
      accesses,compulsory,capacity,conflict:out unsigned(31 downto 0));
end entity;
architecture rtl of cache_3c_policies is
 constant LINES:positive:=SETS*ASSOC;
 type block_array is array(0 to LINES-1) of unsigned(7 downto 0);
 type age_array is array(0 to LINES-1) of unsigned(31 downto 0);
 type tree_array is array(0 to SETS-1) of std_logic_vector(2 downto 0);
 signal cv,sv:std_logic_vector(0 to LINES-1):=(others=>'0');
 signal cb,sb:block_array:=(others=>(others=>'0')); signal ca,sa:age_array:=(others=>(others=>'0'));
 signal seen:std_logic_vector(0 to 255):=(others=>'0'); signal tree:tree_array:=(others=>(others=>'0'));
 signal lfsr:std_logic_vector(7 downto 0):=x"01"; signal timestamp:unsigned(31 downto 0):=(others=>'0');
 signal ac,cc,kc,fc:unsigned(31 downto 0):=(others=>'0');
begin
 assert ASSOC<=4 and POLICY<=3 report "unsupported cache configuration" severity failure;
 accesses<=ac; compulsory<=cc; capacity<=kc; conflict<=fc;
 process(clk)
  variable st,cway,cvictim,sway,svictim,w,sw,idx:integer;
  variable ch,sh,ce,se:boolean;
 begin
  if rising_edge(clk) then
   if reset='1' then
    hit<='0'; miss_kind<=(others=>'0'); ac<=(others=>'0'); cc<=(others=>'0'); kc<=(others=>'0'); fc<=(others=>'0');
    timestamp<=(others=>'0'); lfsr<=x"01"; seen<=(others=>'0'); tree<=(others=>(others=>'0'));
    cv<=(others=>'0'); sv<=(others=>'0'); cb<=(others=>(others=>'0')); sb<=(others=>(others=>'0'));
    ca<=(others=>(others=>'0')); sa<=(others=>(others=>'0'));
   elsif valid='1' then
    st:=to_integer(block_addr) mod SETS; cway:=0; cvictim:=0; sway:=0; svictim:=0;
    ch:=false; sh:=false; ce:=false; se:=false;
    for i in 0 to ASSOC-1 loop
     if cv(st*ASSOC+i)='1' and cb(st*ASSOC+i)=block_addr then ch:=true; cway:=i; end if;
     if cv(st*ASSOC+i)='0' and not ce then ce:=true; cvictim:=i; end if;
    end loop;
    if not ce then
     if POLICY=2 then cvictim:=to_integer(unsigned(lfsr)) mod ASSOC;
     elsif POLICY=3 then
      if ASSOC=1 then cvictim:=0;
      elsif ASSOC=2 then if tree(st)(1)='1' then cvictim:=1; else cvictim:=0; end if;
      elsif tree(st)(0)='0' then if tree(st)(1)='1' then cvictim:=1; else cvictim:=0; end if;
      elsif ASSOC=3 then cvictim:=2;
      elsif tree(st)(2)='1' then cvictim:=3; else cvictim:=2; end if;
     else
      for i in 1 to ASSOC-1 loop if ca(st*ASSOC+i)<ca(st*ASSOC+cvictim) then cvictim:=i; end if; end loop;
     end if;
    end if;
    for i in 0 to LINES-1 loop
     if sv(i)='1' and sb(i)=block_addr then sh:=true; sway:=i; end if;
     if sv(i)='0' and not se then se:=true; svictim:=i; end if;
    end loop;
    if not se then for i in 1 to LINES-1 loop if sa(i)<sa(svictim) then svictim:=i; end if; end loop; end if;
    ac<=ac+1; timestamp<=timestamp+1; miss_kind<=(others=>'0'); seen(to_integer(block_addr))<='1';
    if ch then hit<='1'; w:=cway; else hit<='0'; w:=cvictim; end if;
    idx:=st*ASSOC+w;
    if not ch then
     cv(idx)<='1'; cb(idx)<=block_addr; ca(idx)<=timestamp;
     if seen(to_integer(block_addr))='0' then cc<=cc+1; miss_kind<=to_unsigned(1,2);
     elsif not sh then kc<=kc+1; miss_kind<=to_unsigned(2,2);
     else fc<=fc+1; miss_kind<=to_unsigned(3,2); end if;
     if POLICY=2 then lfsr<=lfsr(6 downto 0) & (lfsr(7) xor lfsr(5) xor lfsr(4) xor lfsr(3)); end if;
    elsif POLICY=0 then ca(idx)<=timestamp; end if;
    if w<2 then
     tree(st)(0)<='1'; if w=0 then tree(st)(1)<='1'; else tree(st)(1)<='0'; end if;
    else
     tree(st)(0)<='0'; if w=2 then tree(st)(2)<='1'; else tree(st)(2)<='0'; end if;
    end if;
    if sh then sw:=sway; else sw:=svictim; end if;
    sv(sw)<='1'; sb(sw)<=block_addr; sa(sw)<=timestamp;
   end if;
  end if;
 end process;
end architecture;
