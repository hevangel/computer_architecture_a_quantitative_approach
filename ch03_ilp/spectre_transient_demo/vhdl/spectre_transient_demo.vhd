library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity spectre_transient_demo is
 generic(BRANCH_LATENCY:positive:=5);
 port(clk,reset,host_we:in std_logic; host_addr,host_data:in unsigned(7 downto 0);
      flush,start:in std_logic; index_value:in unsigned(7 downto 0); bound:in unsigned(8 downto 0);
      mitigation_en:in std_logic; probe_index:in unsigned(7 downto 0);
      probe_cycles,arch_value:out unsigned(7 downto 0); busy,done,transient_load,transient_touch:out std_logic);
end entity;
architecture rtl of spectre_transient_demo is
 type secret_array is array(0 to 255) of unsigned(7 downto 0);
 signal secret:secret_array; signal cached:std_logic_vector(255 downto 0):=(others=>'0');
 signal held_index,loaded:unsigned(7 downto 0):=(others=>'0');
 signal allowed,mitigate,resolved,active:std_logic:='0';
 signal timer:natural range 0 to BRANCH_LATENCY:=0; signal phase:natural range 0 to 2:=0;
begin
 busy<=active; probe_cycles<=to_unsigned(1,8) when cached(to_integer(probe_index))='1' else to_unsigned(10,8);
 process(clk)
 begin
  if rising_edge(clk) then
   if reset='1' then
    cached<=(others=>'0'); arch_value<=(others=>'0'); active<='0'; done<='0'; transient_load<='0'; transient_touch<='0';
    held_index<=(others=>'0'); loaded<=(others=>'0'); allowed<='0'; mitigate<='0'; resolved<='0'; timer<=0; phase<=0;
   else
    done<='0';
    if active='0' then
     if host_we='1' then secret(to_integer(host_addr))<=host_data; end if;
     if flush='1' then cached<=(others=>'0'); end if;
     if start='1' then
      held_index<=index_value;
      if resize(index_value,9)<bound then allowed<='1'; else allowed<='0'; end if;
      mitigate<=mitigation_en; timer<=BRANCH_LATENCY; resolved<='0'; phase<=0; active<='1';
      transient_load<='0'; transient_touch<='0';
     end if;
    else
     if timer>0 then timer<=timer-1; if timer=1 then resolved<='1'; end if; end if;
     if phase=0 and (mitigate='0' or resolved='1') and (resolved='0' or allowed='1') then
      loaded<=secret(to_integer(held_index)); phase<=1; if resolved='0' then transient_load<='1'; end if;
     elsif phase=1 and (resolved='0' or allowed='1') then
      cached(to_integer(loaded))<='1'; phase<=2; if resolved='0' then transient_touch<='1'; end if;
     end if;
     if resolved='1' and (allowed='0' or phase=2) then
      if allowed='1' then arch_value<=loaded; end if;
      active<='0'; done<='1';
     end if;
    end if;
   end if;
  end if;
 end process;
end architecture;
