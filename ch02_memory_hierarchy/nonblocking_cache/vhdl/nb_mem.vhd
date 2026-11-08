-- Main memory model for nb_cache: one request per cycle, in order, with occupancy and a fixed read latency.
--   * a request is accepted in a cycle with mem_ready = '1'; a write keeps the port busy for WR_OCC cycles (including the accepting cycle), a read for RD_OCC;
--   * a write takes effect at once (functionally); a read samples the line at acceptance and returns it MEM_LAT cycles later (mem_rvalid in cycle accept + MEM_LAT)
--     together with the tag it was issued with.
-- `violation` is raised if the cache ever presents a request while mem_ready is low.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nb_mem is
  generic (MEM_LAT : positive := 10; WR_OCC : positive := 4; RD_OCC : positive := 1);
  port (
    clk, rst_n : in  std_logic;
    mem_valid, mem_write : in std_logic;
    mem_addr   : in  natural range 0 to 255;
    mem_wdata  : in  std_logic_vector(31 downto 0);
    mem_tag    : in  natural range 0 to 3;
    mem_ready  : out std_logic;
    mem_rvalid : out std_logic;
    mem_rtag   : out natural range 0 to 3;
    mem_rline  : out std_logic_vector(127 downto 0);
    dbg_addr   : in  natural range 0 to 255;
    dbg_data   : out std_logic_vector(31 downto 0);
    violation  : out std_logic
  );
end entity;

architecture rtl of nb_mem is
  type word_arr is array (0 to 255) of unsigned(31 downto 0);
  type bool_arr is array (0 to 15) of boolean;
  type nat_arr  is array (0 to 15) of natural range 0 to 3;
  type line_arr is array (0 to 15) of std_logic_vector(127 downto 0);
  function init_mem return word_arr is
    variable r : word_arr;
  begin
    for a in 0 to 255 loop r(a) := x"5A000000" + to_unsigned(a * 17, 32); end loop;
    return r;
  end function;
  signal arr  : word_arr := init_mem;
  signal busy : natural range 0 to 15 := 0;
  signal sv_v : bool_arr := (others => false);
  signal sv_tag : nat_arr := (others => 0);
  signal sv_line : line_arr := (others => (others => '0'));
  signal viol : std_logic := '0';
begin
  mem_ready  <= '1' when busy = 0 else '0';
  mem_rvalid <= '1' when sv_v(MEM_LAT - 1) else '0';
  mem_rtag   <= sv_tag(MEM_LAT - 1);
  mem_rline  <= sv_line(MEM_LAT - 1);
  dbg_data   <= std_logic_vector(arr(dbg_addr));
  violation  <= viol;

  process (clk, rst_n)
    variable base : natural;
  begin
    if rst_n = '0' then
      busy <= 0;  viol <= '0';  sv_v <= (others => false);
      arr <= init_mem;
    elsif rising_edge(clk) then
      for i in 1 to 15 loop sv_v(i) <= sv_v(i-1);  sv_tag(i) <= sv_tag(i-1);  sv_line(i) <= sv_line(i-1); end loop;
      sv_v(0) <= false;
      if busy /= 0 then busy <= busy - 1; end if;
      if mem_valid = '1' then
        if busy /= 0 then viol <= '1';
        elsif mem_write = '1' then arr(mem_addr) <= unsigned(mem_wdata);  busy <= WR_OCC - 1;
        else
          base := (mem_addr / 4) * 4;
          sv_v(0) <= true;  sv_tag(0) <= mem_tag;
          sv_line(0) <= std_logic_vector(arr(base + 3)) & std_logic_vector(arr(base + 2)) & std_logic_vector(arr(base + 1)) & std_logic_vector(arr(base));
          busy <= RD_OCC - 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
