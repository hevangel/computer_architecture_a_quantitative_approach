library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity way_predict_vipt is
 generic(PAGE_BITS:positive:=12);
 port(clk,reset,req_valid,req_write:in std_logic; req_vaddr,req_paddr:in unsigned(15 downto 0); req_wdata:in unsigned(31 downto 0);
      req_ready,resp_valid,resp_fault:out std_logic; resp_data:out unsigned(31 downto 0); config_safe,refill_busy:out std_logic;
      refill_word:out unsigned(1 downto 0); stat_fast,stat_slow,stat_miss,stat_way_reads:out unsigned(31 downto 0);
      dbg_paddr:in unsigned(15 downto 0); dbg_memory:out unsigned(31 downto 0));
end;
architecture rtl of way_predict_vipt is
 type state_t is (IDLE,PROBE,FILL); signal state:state_t:=IDLE;
 type bit8 is array(0 to 7) of std_logic; type bit4 is array(0 to 3) of std_logic;
 type tag_array is array(0 to 7) of unsigned(9 downto 0); type cache_array is array(0 to 31) of unsigned(31 downto 0);
 type memory_array is array(0 to 16383) of unsigned(31 downto 0);
 signal valid:bit8:=(others=>'0'); signal predict:bit4:=(others=>'0'); signal tag:tag_array:=(others=>(others=>'0'));
 signal cache:cache_array:=(others=>(others=>'0')); signal memory:memory_array:=(others=>(others=>'0'));
 signal address_q:unsigned(15 downto 0):=(others=>'0'); signal data_q:unsigned(31 downto 0):=(others=>'0');
 signal set_q,off_q,beat:unsigned(1 downto 0):=(others=>'0'); signal write_q,target_q:std_logic:='0';
 signal fast,slow,miss,way_reads:unsigned(31 downto 0):=(others=>'0');
 constant SAFE:boolean:=PAGE_BITS>=6 and PAGE_BITS<=16;
 function low_mask(n:natural) return unsigned is begin return shift_right(to_unsigned(65535,16),16-n); end;
begin
 assert PAGE_BITS<=16 report "PAGE_BITS out of range" severity failure;
 config_safe<='1' when SAFE else '0'; req_ready<='1' when state=IDLE else '0'; refill_busy<='1' when state=FILL else '0';
 refill_word<=off_q+beat; dbg_memory<=memory(to_integer(dbg_paddr(15 downto 2)));
 stat_fast<=fast; stat_slow<=slow; stat_miss<=miss; stat_way_reads<=way_reads;
 process(clk)
  variable entry,set_index,word_index,mem_index,next_word:integer; variable selected:std_logic;
 begin
  if rising_edge(clk) then
   if reset='1' then
    state<=IDLE; resp_valid<='0'; resp_fault<='0'; resp_data<=(others=>'0'); beat<=(others=>'0');
    fast<=(others=>'0'); slow<=(others=>'0'); miss<=(others=>'0'); way_reads<=(others=>'0');
    valid<=(others=>'0'); predict<=(others=>'0'); tag<=(others=>(others=>'0')); cache<=(others=>(others=>'0'));
    for i in 0 to 16383 loop memory(i)<=x"10000000"+to_unsigned(i,32); end loop;
   else
    resp_valid<='0'; resp_fault<='0';
    case state is
     when IDLE =>
      if req_valid='1' then
       if not SAFE or (req_vaddr and low_mask(PAGE_BITS))/=(req_paddr and low_mask(PAGE_BITS)) or req_vaddr(1 downto 0)/="00" then
        resp_valid<='1'; resp_fault<='1'; resp_data<=(others=>'0');
       else
        set_index:=to_integer(req_vaddr(5 downto 4)); entry:=set_index*2;
        if predict(set_index)='1' then entry:=entry+1; end if; way_reads<=way_reads+1;
        if valid(entry)='1' and tag(entry)=req_paddr(15 downto 6) then
         fast<=fast+1; resp_valid<='1'; word_index:=entry*4+to_integer(req_vaddr(3 downto 2));
         if req_write='1' then cache(word_index)<=req_wdata; memory(to_integer(req_paddr(15 downto 2)))<=req_wdata; resp_data<=req_wdata;
         else resp_data<=cache(word_index); end if;
        else
         address_q<=req_paddr; set_q<=req_vaddr(5 downto 4); off_q<=req_vaddr(3 downto 2); write_q<=req_write; data_q<=req_wdata; state<=PROBE;
        end if;
       end if;
      end if;
     when PROBE =>
      set_index:=to_integer(set_q); entry:=set_index*2;
      if predict(set_index)='0' then entry:=entry+1; end if; way_reads<=way_reads+1;
      if valid(entry)='1' and tag(entry)=address_q(15 downto 6) then
       slow<=slow+1; predict(set_index)<=not predict(set_index); resp_valid<='1'; state<=IDLE;
       word_index:=entry*4+to_integer(off_q);
       if write_q='1' then cache(word_index)<=data_q; memory(to_integer(address_q(15 downto 2)))<=data_q; resp_data<=data_q;
       else resp_data<=cache(word_index); end if;
      else
       miss<=miss+1;
       if valid(set_index*2)='0' then target_q<='0';
       elsif valid(set_index*2+1)='0' then target_q<='1';
       else target_q<=not predict(set_index); end if;
       beat<=(others=>'0'); state<=FILL;
      end if;
     when FILL =>
      next_word:=to_integer(off_q+beat); entry:=to_integer(set_q)*2; if target_q='1' then entry:=entry+1; end if;
      mem_index:=to_integer(address_q(15 downto 4))*4+next_word; word_index:=entry*4+next_word;
      if beat=0 then
       resp_valid<='1';
       if write_q='1' then cache(word_index)<=data_q; memory(mem_index)<=data_q; resp_data<=data_q;
       else cache(word_index)<=memory(mem_index); resp_data<=memory(mem_index); end if;
      else cache(word_index)<=memory(mem_index); end if;
      if beat=3 then valid(entry)<='1'; tag(entry)<=address_q(15 downto 6); predict(to_integer(set_q))<=target_q; state<=IDLE;
      else beat<=beat+1; end if;
    end case;
   end if;
  end if;
 end process;
end architecture;
