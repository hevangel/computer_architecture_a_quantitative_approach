library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity simt_memory_engine is
 port(clk,reset,start,shared_mode:in std_logic;
      lane_addresses:in std_logic_vector(1023 downto 0); lane_mask:in std_logic_vector(31 downto 0);
      busy,done,req_valid:out std_logic; req_ready:in std_logic;
      req_lane_mask,req_line_address:out std_logic_vector(31 downto 0); accepted_requests:out unsigned(5 downto 0));
end entity;
architecture rtl of simt_memory_engine is
 signal addresses:std_logic_vector(1023 downto 0):=(others=>'0');
 signal pending,selected:std_logic_vector(31 downto 0):=(others=>'0');
 signal shared_latched,active:std_logic:='0';
 signal line_id:std_logic_vector(25 downto 0):=(others=>'0');
 signal count:unsigned(5 downto 0):=(others=>'0');
begin
 busy<=active; req_valid<=active; req_lane_mask<=selected; accepted_requests<=count;
 req_line_address<=(others=>'0') when shared_latched='1' else line_id & "000000";
 process(all)
  variable vsel,banks:std_logic_vector(31 downto 0); variable lid:std_logic_vector(25 downto 0);
  variable found:boolean; variable bank:integer;
 begin
  vsel:=(others=>'0'); banks:=(others=>'0'); lid:=(others=>'0'); found:=false;
  if shared_latched='1' then
   for lane in 0 to 31 loop
    if pending(lane)='1' then
     bank:=to_integer(unsigned(addresses(lane*32+6 downto lane*32+2)));
     if banks(bank)='0' then banks(bank):='1'; vsel(lane):='1'; end if;
    end if;
   end loop;
  else
   for lane in 0 to 31 loop
    if pending(lane)='1' and not found then lid:=addresses(lane*32+31 downto lane*32+6); found:=true; end if;
   end loop;
   for lane in 0 to 31 loop
    if pending(lane)='1' and addresses(lane*32+31 downto lane*32+6)=lid then vsel(lane):='1'; end if;
   end loop;
  end if;
  selected<=vsel; line_id<=lid;
 end process;
 process(clk)
 begin
  if rising_edge(clk) then
   if reset='1' then active<='0'; done<='0'; pending<=(others=>'0'); addresses<=(others=>'0'); shared_latched<='0'; count<=(others=>'0');
   else
    done<='0';
    if active='0' and start='1' then
      addresses<=lane_addresses; pending<=lane_mask; shared_latched<=shared_mode; count<=(others=>'0');
      if lane_mask=x"00000000" then active<='0'; done<='1'; else active<='1'; end if;
    elsif active='1' and req_ready='1' then
      count<=count+1; pending<=pending and not selected;
      if (pending and not selected)=x"00000000" then active<='0'; done<='1'; end if;
    end if;
   end if;
  end if;
 end process;
end architecture;
