library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity tage_predictor is
 port(clk,reset:in std_logic; pc:in unsigned(15 downto 0); update_valid,actual_taken:in std_logic;
      prediction,gshare_prediction:out std_logic; provider:out unsigned(1 downto 0); history:out unsigned(17 downto 0));
end entity;
architecture rtl of tage_predictor is
 type base_array is array(0 to 15) of unsigned(1 downto 0);
 type tag_array is array(0 to 47) of unsigned(7 downto 0);
 type count_array is array(0 to 47) of unsigned(2 downto 0);
 type useful_array is array(0 to 47) of unsigned(1 downto 0);
 type index_array is array(0 to 2) of natural range 0 to 15;
 type query_tag_array is array(0 to 2) of unsigned(7 downto 0);
 signal base,gshare:base_array:=(others=>"01"); signal valid:std_logic_vector(0 to 47):=(others=>'0');
 signal tags:tag_array:=(others=>(others=>'0')); signal counters:count_array:=(others=>"011"); signal useful:useful_array:=(others=>(others=>'0'));
 signal hist:unsigned(17 downto 0):=(others=>'0'); signal bi,gi:natural range 0 to 15;
 signal idx:index_array; signal tag:query_tag_array; signal pred,alt,gpred:std_logic; signal prov:natural range 0 to 3;
 function sat2(x:unsigned(1 downto 0);up:std_logic) return unsigned is
 begin if up='1' then if x=3 then return x; else return x+1; end if; else if x=0 then return x; else return x-1; end if; end if; end;
 function sat3(x:unsigned(2 downto 0);up:std_logic) return unsigned is
 begin if up='1' then if x=7 then return x; else return x+1; end if; else if x=0 then return x; else return x-1; end if; end if; end;
begin
 history<=hist; prediction<=pred; gshare_prediction<=gpred; provider<=to_unsigned(prov,2);
 process(all)
  variable h:unsigned(17 downto 0); variable ix:index_array; variable tg:query_tag_array;
  variable base_i,g_i,p:natural; variable pp,aa:std_logic;
 begin
  base_i:=to_integer(pc(5 downto 2)); g_i:=to_integer(pc(5 downto 2) xor hist(3 downto 0));
  pp:=base(base_i)(1); aa:=pp; p:=0;
  for b in 0 to 2 loop
   case b is when 0=>h:=hist and to_unsigned(3,18); when 1=>h:=hist and to_unsigned(63,18); when others=>h:=hist; end case;
   ix(b):=to_integer(pc(5 downto 2) xor h(3 downto 0));
   tg(b):=resize(shift_right(pc,2),8) xor resize(h,8) xor resize(shift_right(h,8),8) xor resize(shift_right(h,16),8);
   if valid(b*16+ix(b))='1' and tags(b*16+ix(b))=tg(b) then
    aa:=pp; pp:=counters(b*16+ix(b))(2); p:=b+1;
   end if;
  end loop;
  bi<=base_i; gi<=g_i; idx<=ix; tag<=tg; pred<=pp; alt<=aa; prov<=p; gpred<=gshare(g_i)(1);
 end process;
 process(clk)
  variable slot,allocation:integer;
 begin
  if rising_edge(clk) then
   if reset='1' then
    hist<=(others=>'0'); base<=(others=>"01"); gshare<=(others=>"01"); valid<=(others=>'0');
    tags<=(others=>(others=>'0')); counters<=(others=>"011"); useful<=(others=>(others=>'0'));
   elsif update_valid='1' then
    base(bi)<=sat2(base(bi),actual_taken); gshare(gi)<=sat2(gshare(gi),actual_taken);
    if prov/=0 then
     slot:=(prov-1)*16+idx(prov-1); counters(slot)<=sat3(counters(slot),actual_taken);
     if pred/=alt then
      if pred=actual_taken then useful(slot)<=sat2(useful(slot),'1'); else useful(slot)<=sat2(useful(slot),'0'); end if;
     end if;
    end if;
    if pred/=actual_taken then
     allocation:=-1;
     for b in 0 to 2 loop
      if b>=prov and allocation<0 and (valid(b*16+idx(b))='0' or useful(b*16+idx(b))=0) then allocation:=b; end if;
     end loop;
     if allocation>=0 then
      slot:=allocation*16+idx(allocation); valid(slot)<='1'; tags(slot)<=tag(allocation);
      if actual_taken='1' then counters(slot)<="100"; else counters(slot)<="011"; end if; useful(slot)<=(others=>'0');
     else
      for b in 0 to 2 loop
       if b>=prov and valid(b*16+idx(b))='1' and useful(b*16+idx(b))/=0 then useful(b*16+idx(b))<=useful(b*16+idx(b))-1; end if;
      end loop;
     end if;
    end if;
    hist<=hist(16 downto 0) & actual_taken;
   end if;
  end if;
 end process;
end architecture;
