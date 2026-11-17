library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity vector_bank_gather_strip is
  port(clk,reset,mem_we : in std_logic; mem_addr : in unsigned(8 downto 0); mem_wdata : in std_logic_vector(31 downto 0);
       mem_rdata : out std_logic_vector(31 downto 0);
       vec_we : in std_logic; vec_slot : in unsigned(5 downto 0); vec_index : in unsigned(8 downto 0);
       vec_wdata : in std_logic_vector(31 downto 0); vec_result : out std_logic_vector(31 downto 0);
       start,indexed,store : in std_logic; length : in unsigned(6 downto 0); base,stride : in unsigned(8 downto 0);
       busy,done,error : out std_logic; service_cycles,ideal_cycles,bank_stalls : out unsigned(15 downto 0);
       strips : out unsigned(2 downto 0); strip_length : out unsigned(4 downto 0));
end entity;
architecture rtl of vector_bank_gather_strip is
  type memory_type is array(0 to 511) of std_logic_vector(31 downto 0);
  type vector_type is array(0 to 63) of std_logic_vector(31 downto 0);
  type index_type is array(0 to 63) of unsigned(8 downto 0);
  type address_type is array(0 to 15) of unsigned(8 downto 0);
  signal memory:memory_type; signal store_data,result:vector_type; signal indices:index_type;
  signal pending,grants:std_logic_vector(15 downto 0):=(others=>'0');
  signal lane_addr:address_type;
  signal offset,total:unsigned(6 downto 0):=(others=>'0');
  signal base_latched,stride_latched:unsigned(8 downto 0):=(others=>'0');
  signal indexed_latched,store_latched,active:std_logic:='0';
  signal svc,ideal:unsigned(15 downto 0):=(others=>'0');
  signal count:unsigned(4 downto 0):=(others=>'0');
  function chunk_for(n:integer) return integer is
  begin if n>=16 then return 16; else return n; end if; end;
  function mask_for(n:integer) return std_logic_vector is
    variable v:std_logic_vector(15 downto 0):=(others=>'0');
  begin for i in 0 to 15 loop if i<n then v(i):='1'; end if; end loop; return v; end;
begin
  mem_rdata<=memory(to_integer(mem_addr)) when not is_x(std_logic_vector(mem_addr)) else (others=>'0');
  vec_result<=result(to_integer(vec_slot)) when not is_x(std_logic_vector(vec_slot)) else (others=>'0');
  busy<=active; service_cycles<=svc; ideal_cycles<=ideal; bank_stalls<=svc-ideal; strip_length<=count;
  process(all)
    variable used:std_logic_vector(7 downto 0); variable g:std_logic_vector(15 downto 0);
    variable addr:unsigned(8 downto 0); variable slot,bank:integer;
    variable addrs:address_type;
  begin
    used:=(others=>'0'); g:=(others=>'0'); addrs:=(others=>(others=>'0'));
    for lane in 0 to 15 loop
      if pending(lane)='1' then
        slot:=to_integer(offset)+lane;
        if indexed_latched='1' then addr:=indices(slot);
        else addr:=to_unsigned((to_integer(base_latched)+slot*to_integer(stride_latched)) mod 512,9); end if;
        addrs(lane):=addr; bank:=to_integer(addr(2 downto 0));
        if used(bank)='0' then used(bank):='1'; g(lane):='1'; end if;
      end if;
    end loop;
    grants<=g; lane_addr<=addrs;
  end process;
  process(clk)
    variable next_count:integer;
  begin
    if rising_edge(clk) then
      if reset='1' then
        pending<=(others=>'0'); offset<=(others=>'0'); total<=(others=>'0'); active<='0'; done<='0'; error<='0';
        base_latched<=(others=>'0'); stride_latched<=(others=>'0'); indexed_latched<='0'; store_latched<='0';
        svc<=(others=>'0'); ideal<=(others=>'0'); strips<=(others=>'0'); count<=(others=>'0');
      else
        done<='0';
        if active='0' then
          if mem_we='1' then memory(to_integer(mem_addr))<=mem_wdata; end if;
          if vec_we='1' then indices(to_integer(vec_slot))<=vec_index; store_data(to_integer(vec_slot))<=vec_wdata; end if;
          if start='1' then
            error<='0'; svc<=(others=>'0'); ideal<=(others=>'0'); strips<=(others=>'0'); count<=(others=>'0'); offset<=(others=>'0');
            if length>64 then error<='1'; done<='1';
            elsif length=0 then done<='1';
            else
              active<='1'; total<=length; indexed_latched<=indexed; store_latched<=store;
              base_latched<=base; stride_latched<=stride;
              next_count:=chunk_for(to_integer(length)); count<=to_unsigned(next_count,5); pending<=mask_for(next_count);
              ideal<=to_unsigned((next_count+7)/8,16); strips<=to_unsigned(1,3);
            end if;
          end if;
        else
          svc<=svc+1;
          for lane in 0 to 15 loop
            if grants(lane)='1' then
              if store_latched='1' then memory(to_integer(lane_addr(lane)))<=store_data(to_integer(offset)+lane);
              else result(to_integer(offset)+lane)<=memory(to_integer(lane_addr(lane))); end if;
            end if;
          end loop;
          if (pending and not grants)=x"0000" then
            if to_integer(offset)+to_integer(count)>=to_integer(total) then active<='0'; done<='1'; pending<=(others=>'0');
            else
              offset<=offset+resize(count,7);
              next_count:=chunk_for(to_integer(total)-to_integer(offset)-to_integer(count));
              count<=to_unsigned(next_count,5); pending<=mask_for(next_count);
              ideal<=ideal+to_unsigned((next_count+7)/8,16); strips<=strips+1;
            end if;
          else pending<=pending and not grants; end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
