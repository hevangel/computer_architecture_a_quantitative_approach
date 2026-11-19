library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_dma_split_bus_coherence is end;
architecture tb of tb_dma_split_bus_coherence is
  signal clk : std_logic:='0';
  signal reset : std_logic:='1';
  signal cpu_valid,cpu_write,start,direction,snoop,irq_ack,periph_in_valid,periph_out_ready : std_logic:='0';
  signal cpu_ready,cpu_rvalid,busy,irq,desc_error,periph_in_ready,periph_out_valid : std_logic;
  signal cpu_addr,desc_addr : std_logic_vector(3 downto 0):=(others=>'0');
  signal desc_length : std_logic_vector(4 downto 0):=(others=>'0');
  signal cpu_wdata,periph_in_data : std_logic_vector(31 downto 0):=(others=>'0');
  signal cpu_rdata,periph_out_data : std_logic_vector(31 downto 0);
begin
  clk<=not clk after 5 ns;
  dut: entity work.dma_split_bus_coherence port map(clk,reset,cpu_valid,cpu_write,cpu_addr,cpu_wdata,
      cpu_ready,cpu_rvalid,cpu_rdata,start,direction,snoop,irq_ack,desc_addr,desc_length,busy,irq,desc_error,
      periph_in_valid,periph_in_ready,periph_in_data,periph_out_valid,periph_out_ready,periph_out_data);
  process
    procedure cpu_store(a,v : natural) is
    begin
      wait until falling_edge(clk); cpu_valid<='1'; cpu_write<='1'; cpu_addr<=std_logic_vector(to_unsigned(a,4)); cpu_wdata<=std_logic_vector(to_unsigned(v,32));
      while cpu_ready/='1' loop wait until falling_edge(clk); end loop;
      wait until falling_edge(clk); cpu_valid<='0'; cpu_write<='0';
    end procedure;
    procedure cpu_load(a,v : natural) is
    begin
      wait until falling_edge(clk); cpu_valid<='1'; cpu_write<='0'; cpu_addr<=std_logic_vector(to_unsigned(a,4));
      while cpu_ready/='1' loop wait until falling_edge(clk); end loop;
      wait until falling_edge(clk);
      assert cpu_rvalid='1' and cpu_rdata=std_logic_vector(to_unsigned(v,32)) report "CPU read mismatch" severity failure;
      cpu_valid<='0';
    end procedure;
    procedure launch(a,n : natural; dir,sn : std_logic) is
    begin
      wait until falling_edge(clk); desc_addr<=std_logic_vector(to_unsigned(a,4)); desc_length<=std_logic_vector(to_unsigned(n,5)); direction<=dir; snoop<=sn; start<='1';
      wait until falling_edge(clk); start<='0';
    end procedure;
    procedure send_word(v : natural) is
    begin
      wait until falling_edge(clk); periph_in_data<=std_logic_vector(to_unsigned(v,32)); periph_in_valid<='1';
      while periph_in_ready/='1' loop wait until falling_edge(clk); end loop;
      wait until falling_edge(clk); periph_in_valid<='0';
    end procedure;
    procedure receive_word(v : natural) is
    begin
      while periph_out_valid/='1' loop wait until falling_edge(clk); end loop;
      assert periph_out_data=std_logic_vector(to_unsigned(v,32)) report "DMA output mismatch" severity failure;
      for i in 1 to 2 loop
        wait until falling_edge(clk);
        assert periph_out_valid='1' and periph_out_data=std_logic_vector(to_unsigned(v,32)) report "backpressure mismatch" severity failure;
      end loop;
      periph_out_ready<='1'; wait until falling_edge(clk); periph_out_ready<='0';
    end procedure;
  begin
    wait until falling_edge(clk); wait until falling_edge(clk); reset<='0';
    send_word(201); send_word(202); send_word(203); send_word(204);
    assert periph_in_ready='0' report "full input FIFO accepted data" severity failure;
    launch(8,4,'0','1'); while irq/='1' loop wait until falling_edge(clk); end loop;
    cpu_load(8,201); cpu_load(9,202); cpu_load(10,203); cpu_load(11,204);
    launch(8,4,'1','1'); while irq/='1' loop wait until falling_edge(clk); end loop;
    receive_word(201); receive_word(202); receive_word(203); receive_word(204);
    cpu_store(2,85); cpu_load(2,85);
    launch(2,3,'0','0'); send_word(11); send_word(22); send_word(33);
    while irq/='1' loop wait until falling_edge(clk); end loop;
    cpu_load(2,85); cpu_load(3,22); cpu_load(2,11); cpu_load(4,33); cpu_load(2,11);
    launch(2,3,'0','1'); send_word(101); send_word(102); send_word(103);
    while irq/='1' loop wait until falling_edge(clk); end loop;
    cpu_load(2,101); cpu_load(3,102); cpu_load(4,103);
    launch(2,3,'1','1'); receive_word(101); receive_word(102); receive_word(103);
    while irq/='1' loop wait until falling_edge(clk); end loop;
    wait until falling_edge(clk); irq_ack<='1'; wait until falling_edge(clk); irq_ack<='0';
    assert irq='0' report "IRQ did not clear" severity failure;
    launch(15,2,'0','1'); assert desc_error='1' and busy='0' report "invalid descriptor accepted" severity failure;
    launch(15,31,'0','1'); assert desc_error='1' and busy='0' report "overflow descriptor accepted" severity failure;
    launch(0,0,'0','1'); assert desc_error='1' and busy='0' report "zero descriptor accepted" severity failure;
    report "TEST PASSED"; finish;
  end process;
  process begin wait for 20 us; assert false report "timeout" severity failure; end process;
end architecture;
