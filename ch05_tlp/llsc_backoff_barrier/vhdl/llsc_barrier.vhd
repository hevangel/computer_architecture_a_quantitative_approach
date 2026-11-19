library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity llsc_barrier is
 port(clk,reset,cmd_valid:in std_logic; cmd_core,cmd_op:in unsigned(1 downto 0); cmd_addr:in unsigned(3 downto 0);
      cmd_wdata:in unsigned(31 downto 0); rsp_valid,sc_success:out std_logic; rsp_data,invalidations:out unsigned(31 downto 0);
      arrive:in std_logic; arrive_core:in unsigned(1 downto 0); waiting,local_sense:out std_logic_vector(3 downto 0);
      global_sense,barrier_release:out std_logic);
end entity;
architecture rtl of llsc_barrier is
 type memory_t is array(0 to 15) of unsigned(31 downto 0); type addr_t is array(0 to 3) of unsigned(3 downto 0);
 signal memory:memory_t:=(others=>(others=>'0')); signal reservations:std_logic_vector(3 downto 0):=(others=>'0');
 signal reserved_addr:addr_t:=(others=>(others=>'0')); signal inv:unsigned(31 downto 0):=(others=>'0');
 signal waits,locals:std_logic_vector(3 downto 0):=(others=>'0'); signal sense:std_logic:='0';
begin
 waiting<=waits; local_sense<=locals; global_sense<=sense; invalidations<=inv;
 process(clk)
  variable killed:integer; variable arrivals:std_logic_vector(3 downto 0); variable core:integer;
 begin
  if rising_edge(clk) then
   if reset='1' then
    rsp_valid<='0'; sc_success<='0'; rsp_data<=(others=>'0'); inv<=(others=>'0'); reservations<=(others=>'0');
    waits<=(others=>'0'); locals<=(others=>'0'); sense<='0'; barrier_release<='0';
    memory<=(others=>(others=>'0')); reserved_addr<=(others=>(others=>'0'));
   else
    rsp_valid<='0'; sc_success<='0'; barrier_release<='0';
    if cmd_valid='1' then
     rsp_valid<='1'; rsp_data<=memory(to_integer(cmd_addr)); killed:=0; core:=to_integer(cmd_core);
     case cmd_op is
      when "00"=>null;
      when "01"=>reservations(core)<='1'; reserved_addr(core)<=cmd_addr;
      when "10"=>
       reservations(core)<='0';
       if reservations(core)='1' and reserved_addr(core)=cmd_addr then
        sc_success<='1'; memory(to_integer(cmd_addr))<=cmd_wdata;
        for i in 0 to 3 loop
         if reservations(i)='1' and reserved_addr(i)=cmd_addr then
          reservations(i)<='0'; if i/=core then killed:=killed+1; end if;
         end if;
        end loop;
       end if;
      when others=>
       memory(to_integer(cmd_addr))<=cmd_wdata;
       for i in 0 to 3 loop
        if reservations(i)='1' and reserved_addr(i)=cmd_addr then
         reservations(i)<='0'; if i/=core then killed:=killed+1; end if;
        end if;
       end loop;
     end case;
     inv<=inv+to_unsigned(killed,32);
    end if;
    if arrive='1' and waits(to_integer(arrive_core))='0' then
     locals(to_integer(arrive_core))<=not locals(to_integer(arrive_core)); arrivals:=waits; arrivals(to_integer(arrive_core)):='1';
     if arrivals="1111" then waits<=(others=>'0'); sense<=not sense; barrier_release<='1'; else waits<=arrivals; end if;
    end if;
   end if;
  end if;
 end process;
end architecture;
