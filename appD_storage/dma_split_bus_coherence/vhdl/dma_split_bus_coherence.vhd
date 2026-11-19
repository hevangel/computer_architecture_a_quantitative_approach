library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity dma_coherence_core is
  port (clk, reset, cpu_valid, cpu_write : in std_logic;
        cpu_addr : in std_logic_vector(3 downto 0); cpu_wdata : in std_logic_vector(31 downto 0);
        cpu_ready, cpu_rvalid : out std_logic; cpu_rdata : out std_logic_vector(31 downto 0);
        start, direction, snoop, irq_ack : in std_logic;
        desc_addr : in std_logic_vector(3 downto 0); desc_length : in std_logic_vector(4 downto 0);
        busy, irq, desc_error : out std_logic;
        periph_in_valid : in std_logic; periph_in_ready : out std_logic; periph_in_data : in std_logic_vector(31 downto 0);
        periph_out_valid : out std_logic; periph_out_ready : in std_logic; periph_out_data : out std_logic_vector(31 downto 0));
end entity;
architecture rtl of dma_coherence_core is
  type state_type is (idle, input_wait, request, response, output_wait);
  type memory_type is array(0 to 15) of std_logic_vector(31 downto 0);
  signal state : state_type;
  signal memory : memory_type;
  signal cache_valid, mode, do_snoop, pending, pending_write : std_logic;
  signal cache_tag, address, pending_addr : unsigned(3 downto 0);
  signal cache_data, payload, pending_data : std_logic_vector(31 downto 0);
  signal remaining : unsigned(4 downto 0);
begin
  busy <= '0' when state=idle else '1';
  cpu_ready <= not pending;
  periph_in_ready <= '1' when state=input_wait else '0';
  periph_out_valid <= '1' when state=output_wait else '0';
  periph_out_data <= payload;
  process(clk)
  begin
    if rising_edge(clk) then
      if reset='1' then
        state<=idle; cache_valid<='0'; cache_tag<=(others=>'0'); cache_data<=(others=>'0');
        address<=(others=>'0'); remaining<=(others=>'0'); mode<='0'; do_snoop<='0'; payload<=(others=>'0');
        pending<='0'; pending_write<='0'; pending_addr<=(others=>'0'); pending_data<=(others=>'0');
        irq<='0'; desc_error<='0'; cpu_rvalid<='0'; cpu_rdata<=(others=>'0'); memory<=(others=>(others=>'0'));
      else
        cpu_rvalid<='0';
        if irq_ack='1' then irq<='0'; end if;
        if cpu_valid='1' and pending='0' then
          if cpu_write='1' then
            memory(to_integer(unsigned(cpu_addr)))<=cpu_wdata;
            if cache_valid='1' and cache_tag=unsigned(cpu_addr) then cache_data<=cpu_wdata; end if;
          else
            cpu_rvalid<='1';
            if cache_valid='1' and cache_tag=unsigned(cpu_addr) then cpu_rdata<=cache_data;
            else
              cpu_rdata<=memory(to_integer(unsigned(cpu_addr))); cache_data<=memory(to_integer(unsigned(cpu_addr)));
              cache_tag<=unsigned(cpu_addr); cache_valid<='1';
            end if;
          end if;
        end if;
        if pending='1' then
          pending<='0';
          if pending_write='1' then
            memory(to_integer(pending_addr))<=pending_data;
            if do_snoop='1' and cache_valid='1' and cache_tag=pending_addr then cache_valid<='0'; end if;
          else payload<=memory(to_integer(pending_addr)); end if;
          if pending_write='1' then
            if remaining=1 then state<=idle; irq<='1';
            else remaining<=remaining-1; address<=address+1; state<=input_wait; end if;
          else state<=output_wait; end if;
        end if;
        case state is
          when idle => if start='1' then
            irq<='0';
            if unsigned(desc_length)=0 or resize(unsigned(desc_addr),6)+resize(unsigned(desc_length),6)>16 then desc_error<='1';
            else
              desc_error<='0'; address<=unsigned(desc_addr); remaining<=unsigned(desc_length);
              mode<=direction; do_snoop<=snoop;
              if direction='1' then state<=request; else state<=input_wait; end if;
            end if;
          end if;
          when input_wait => if periph_in_valid='1' then payload<=periph_in_data; state<=request; end if;
          when request => if pending='0' and cpu_valid='0' then
            pending<='1'; pending_write<=not mode; pending_addr<=address; pending_data<=payload; state<=response;
          end if;
          when response => null;
          when output_wait => if periph_out_ready='1' then
            if remaining=1 then state<=idle; irq<='1';
            else remaining<=remaining-1; address<=address+1; state<=request; end if;
          end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
