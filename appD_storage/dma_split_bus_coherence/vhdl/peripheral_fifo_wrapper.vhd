library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity dma_split_bus_coherence is
  port (clk, reset, cpu_valid, cpu_write : in std_logic;
        cpu_addr : in std_logic_vector(3 downto 0); cpu_wdata : in std_logic_vector(31 downto 0);
        cpu_ready, cpu_rvalid : out std_logic; cpu_rdata : out std_logic_vector(31 downto 0);
        start, direction, snoop, irq_ack : in std_logic;
        desc_addr : in std_logic_vector(3 downto 0); desc_length : in std_logic_vector(4 downto 0);
        busy, irq, desc_error : out std_logic;
        periph_in_valid : in std_logic; periph_in_ready : out std_logic; periph_in_data : in std_logic_vector(31 downto 0);
        periph_out_valid : out std_logic; periph_out_ready : in std_logic; periph_out_data : out std_logic_vector(31 downto 0));
end entity;
architecture rtl of dma_split_bus_coherence is
  type fifo_type is array(0 to 3) of std_logic_vector(31 downto 0);
  signal in_fifo,out_fifo : fifo_type;
  signal in_rd,in_wr,out_rd,out_wr : unsigned(1 downto 0) := (others=>'0');
  signal in_count,out_count : unsigned(2 downto 0) := (others=>'0');
  signal core_in_valid,core_in_ready,core_out_valid,core_out_ready : std_logic;
  signal core_in_data,core_out_data : std_logic_vector(31 downto 0);
  signal in_push,in_pop,out_push,out_pop : std_logic;
begin
  periph_in_ready<='1' when in_count<4 else '0';
  periph_out_valid<='1' when out_count/=0 else '0';
  core_in_valid<='1' when in_count/=0 else '0';
  core_out_ready<='1' when out_count<4 else '0';
  core_in_data<=in_fifo(to_integer(in_rd)) when not is_x(std_logic_vector(in_rd)) else (others=>'0');
  periph_out_data<=out_fifo(to_integer(out_rd)) when not is_x(std_logic_vector(out_rd)) else (others=>'0');
  in_push<=periph_in_valid and periph_in_ready;
  in_pop<=core_in_valid and core_in_ready;
  out_push<=core_out_valid and core_out_ready;
  out_pop<=periph_out_valid and periph_out_ready;
  core: entity work.dma_coherence_core port map(clk,reset,cpu_valid,cpu_write,cpu_addr,cpu_wdata,cpu_ready,cpu_rvalid,cpu_rdata,
    start,direction,snoop,irq_ack,desc_addr,desc_length,busy,irq,desc_error,
    core_in_valid,core_in_ready,core_in_data,core_out_valid,core_out_ready,core_out_data);
  process(clk)
  begin
    if rising_edge(clk) then
      if reset='1' then
        in_rd<=(others=>'0'); in_wr<=(others=>'0'); out_rd<=(others=>'0'); out_wr<=(others=>'0');
        in_count<=(others=>'0'); out_count<=(others=>'0');
      else
        if in_push='1' then in_fifo(to_integer(in_wr))<=periph_in_data; in_wr<=in_wr+1; end if;
        if in_pop='1' then in_rd<=in_rd+1; end if;
        if in_push='1' and in_pop='0' then in_count<=in_count+1;
        elsif in_push='0' and in_pop='1' then in_count<=in_count-1; end if;
        if out_push='1' then out_fifo(to_integer(out_wr))<=core_out_data; out_wr<=out_wr+1; end if;
        if out_pop='1' then out_rd<=out_rd+1; end if;
        if out_push='1' and out_pop='0' then out_count<=out_count+1;
        elsif out_push='0' and out_pop='1' then out_count<=out_count-1; end if;
      end if;
    end if;
  end process;
end architecture;
