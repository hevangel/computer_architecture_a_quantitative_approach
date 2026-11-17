library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity simt_coalesce_bankconflict is
 port(clk,reset:in std_logic; lane_addresses:in std_logic_vector(1023 downto 0); lane_mask:in std_logic_vector(31 downto 0);
      global_transactions,shared_replay_cycles:out unsigned(5 downto 0);
      warp:in unsigned(2 downto 0); src_a,src_b,dst:in unsigned(4 downto 0);
      use_a,use_b,write_dst,issue:in std_logic; can_issue:out std_logic;
      wb_valid:in std_logic; wb_warp:in unsigned(2 downto 0); wb_reg:in unsigned(4 downto 0);
      barrier_arrive:in std_logic; barrier_target:in std_logic_vector(7 downto 0);
      barrier_waiting:out std_logic_vector(7 downto 0); barrier_release:out std_logic);
end entity;
architecture rtl of simt_coalesce_bankconflict is
 type scoreboard_type is array(0 to 7) of std_logic_vector(31 downto 0);
 type counts_type is array(0 to 31) of integer range 0 to 32;
 signal scoreboard:scoreboard_type:=(others=>(others=>'0'));
 signal waiting_mask:std_logic_vector(7 downto 0):=(others=>'0');
 signal ready_internal:std_logic;
begin
 barrier_waiting<=waiting_mask; can_issue<=ready_internal;
 process(all)
  variable counts:counts_type; variable unique_count,max_count,bank:integer; variable seen:boolean;
 begin
  counts:=(others=>0); unique_count:=0; max_count:=0;
  for i in 0 to 31 loop
   if lane_mask(i)='1' then
    seen:=false;
    for j in 0 to 31 loop
     if j<i and lane_mask(j)='1' and lane_addresses(i*32+31 downto i*32+6)=lane_addresses(j*32+31 downto j*32+6) then seen:=true; end if;
    end loop;
    if not seen then unique_count:=unique_count+1; end if;
    if not is_x(lane_addresses(i*32+6 downto i*32+2)) then
     bank:=to_integer(unsigned(lane_addresses(i*32+6 downto i*32+2))); counts(bank):=counts(bank)+1;
    end if;
   end if;
  end loop;
  for i in 0 to 31 loop if counts(i)>max_count then max_count:=counts(i); end if; end loop;
  global_transactions<=to_unsigned(unique_count,6); shared_replay_cycles<=to_unsigned(max_count,6);
 end process;
 process(all)
 begin
  ready_internal<='0';
  if not is_x(std_logic_vector(warp)&std_logic_vector(src_a)&std_logic_vector(src_b)&std_logic_vector(dst)) then
   if waiting_mask(to_integer(warp))='0' and (use_a='0' or scoreboard(to_integer(warp))(to_integer(src_a))='0') and
      (use_b='0' or scoreboard(to_integer(warp))(to_integer(src_b))='0') and
      (write_dst='0' or scoreboard(to_integer(warp))(to_integer(dst))='0') then ready_internal<='1'; end if;
  end if;
 end process;
 process(clk)
  variable arriving,combined:std_logic_vector(7 downto 0);
 begin
  if rising_edge(clk) then
   if reset='1' then scoreboard<=(others=>(others=>'0')); waiting_mask<=(others=>'0'); barrier_release<='0';
   else
    barrier_release<='0';
    if wb_valid='1' then scoreboard(to_integer(wb_warp))(to_integer(wb_reg))<='0'; end if;
    if issue='1' and ready_internal='1' and write_dst='1' then scoreboard(to_integer(warp))(to_integer(dst))<='1'; end if;
    if barrier_arrive='1' and barrier_target(to_integer(warp))='1' and barrier_target/=x"00" then
     arriving:=(others=>'0'); arriving(to_integer(warp)):='1'; combined:=waiting_mask or arriving;
     if (combined and barrier_target)=barrier_target then waiting_mask<=waiting_mask and not barrier_target; barrier_release<='1';
     else waiting_mask<=combined; end if;
    end if;
   end if;
  end if;
 end process;
end architecture;
