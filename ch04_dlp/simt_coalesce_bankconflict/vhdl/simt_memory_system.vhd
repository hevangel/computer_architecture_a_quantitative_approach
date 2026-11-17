library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity simt_memory_system is
 port(clk,reset,start,shared_mode,write_op,allow_request:in std_logic;
      lane_addresses,lane_wdata:in std_logic_vector(1023 downto 0); lane_mask:in std_logic_vector(31 downto 0);
      host_we,host_shared:in std_logic; host_addr:in unsigned(7 downto 0); host_wdata:in std_logic_vector(31 downto 0);
      host_rdata:out std_logic_vector(31 downto 0); busy,done,req_valid:out std_logic;
      req_lane_mask,req_line_address:out std_logic_vector(31 downto 0); accepted_requests:out unsigned(5 downto 0);
      lane_rdata:out std_logic_vector(1023 downto 0));
end entity;
architecture rtl of simt_memory_system is
 type memory_type is array(0 to 255) of std_logic_vector(31 downto 0);
 signal global_mem,shared_mem:memory_type;
 signal addresses_latched,data_latched:std_logic_vector(1023 downto 0):=(others=>'0');
 signal shared_latched,write_latched,active,valid:std_logic:='0';
 signal lane_grants:std_logic_vector(31 downto 0);
begin
 host_rdata<=shared_mem(to_integer(host_addr)) when host_shared='1' else global_mem(to_integer(host_addr));
 busy<=active; req_valid<=valid; req_lane_mask<=lane_grants;
 engine:entity work.simt_memory_engine port map(clk,reset,start,shared_mode,lane_addresses,lane_mask,
    active,done,valid,allow_request,lane_grants,req_line_address,accepted_requests);
 process(clk)
  variable addr:integer;
 begin
  if rising_edge(clk) then
   if reset='1' then addresses_latched<=(others=>'0'); data_latched<=(others=>'0'); shared_latched<='0'; write_latched<='0'; lane_rdata<=(others=>'0');
   else
    if active='0' and host_we='1' then
      if host_shared='1' then shared_mem(to_integer(host_addr))<=host_wdata; else global_mem(to_integer(host_addr))<=host_wdata; end if;
    end if;
    if active='0' and start='1' then
      addresses_latched<=lane_addresses; data_latched<=lane_wdata; shared_latched<=shared_mode; write_latched<=write_op; lane_rdata<=(others=>'0');
    end if;
    if valid='1' and allow_request='1' then
      for lane in 0 to 31 loop
       if lane_grants(lane)='1' then
        addr:=to_integer(unsigned(addresses_latched(lane*32+9 downto lane*32+2)));
        if write_latched='1' then
         if shared_latched='1' then shared_mem(addr)<=data_latched(lane*32+31 downto lane*32);
         else global_mem(addr)<=data_latched(lane*32+31 downto lane*32); end if;
        else
         if shared_latched='1' then lane_rdata(lane*32+31 downto lane*32)<=shared_mem(addr);
         else lane_rdata(lane*32+31 downto lane*32)<=global_mem(addr); end if;
        end if;
       end if;
      end loop;
    end if;
   end if;
  end if;
 end process;
end architecture;
