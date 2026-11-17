library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_dsp_qmac_circular_zoloop is end;
architecture tb of tb_dsp_qmac_circular_zoloop is
  signal clk : std_logic:='0'; signal reset : std_logic:='1';
  signal mac_clear,mac_enable,pointer_load,pointer_step,repeat_load,repeat_step : std_logic:='0';
  signal sample,coefficient,rounded_q15 : signed(15 downto 0):=(others=>'0');
  signal accumulator : signed(39 downto 0);
  signal pointer_start,pointer : unsigned(3 downto 0):=(others=>'0');
  signal fft_index,bit_reversed : std_logic_vector(3 downto 0):=(others=>'0');
  signal pointer_modulus : unsigned(4 downto 0):=to_unsigned(16,5);
  signal repeat_count : unsigned(4 downto 0):=(others=>'0');
  signal repeat_active,repeat_last : std_logic;
begin
  clk<=not clk after 5 ns;
  dut: entity work.dsp_qmac_circular_zoloop port map(clk,reset,mac_clear,mac_enable,sample,coefficient,accumulator,rounded_q15,
    pointer_load,pointer_step,pointer_start,pointer_modulus,pointer,fft_index,bit_reversed,repeat_load,repeat_step,repeat_count,repeat_active,repeat_last);
  process
    procedure clear_mac is
    begin wait until falling_edge(clk); mac_clear<='1'; mac_enable<='0'; wait until falling_edge(clk); mac_clear<='0'; end;
    procedure one_product(s,c,expected : integer) is
    begin
      clear_mac; sample<=to_signed(s,16); coefficient<=to_signed(c,16); mac_enable<='1';
      wait until falling_edge(clk); mac_enable<='0';
      assert rounded_q15=to_signed(expected,16) report "rounding mismatch" severity failure;
    end;
    variable idx : std_logic_vector(3 downto 0);
    constant expected_reverse : std_logic_vector(63 downto 0) := x"f7b3d591e6a2c480";
  begin
    wait until falling_edge(clk); wait until falling_edge(clk); reset<='0';
    for i in 0 to 15 loop
      idx:=std_logic_vector(to_unsigned(i,4)); fft_index<=idx; wait for 1 ns;
      assert bit_reversed=expected_reverse(i*4+3 downto i*4) report "bit reverse mismatch" severity failure;
    end loop;
    wait until falling_edge(clk); pointer_start<=to_unsigned(13,4); pointer_load<='1'; repeat_count<=to_unsigned(16,5); repeat_load<='1'; mac_clear<='1';
    wait until falling_edge(clk); pointer_load<='0'; repeat_load<='0'; mac_clear<='0'; pointer_step<='1'; repeat_step<='1'; mac_enable<='1'; coefficient<=to_signed(2048,16);
    for i in 0 to 15 loop
      assert repeat_active='1' and ((i=15 and repeat_last='1') or (i/=15 and repeat_last='0')) report "repeat state mismatch" severity failure;
      sample<=to_signed(to_integer(pointer)*2048,16); wait until falling_edge(clk);
    end loop;
    mac_enable<='0'; pointer_step<='0'; repeat_step<='0';
    assert repeat_active='0' and pointer=13 and accumulator=to_signed(503316480,40) and rounded_q15=to_signed(15360,16) report "FIR mismatch" severity failure;
    one_product(1,16384,0); one_product(3,16384,2); one_product(-1,16384,0); one_product(-3,16384,-2);
    clear_mac; sample<=to_signed(32767,16); coefficient<=to_signed(32767,16); mac_enable<='1';
    for i in 1 to 520 loop wait until falling_edge(clk); end loop;
    mac_enable<='0';
    assert accumulator=signed'(x"7fffffffff") and rounded_q15=to_signed(32767,16) report "positive saturation mismatch" severity failure;
    clear_mac; sample<=to_signed(-32768,16); coefficient<=to_signed(32767,16); mac_enable<='1';
    for i in 1 to 520 loop wait until falling_edge(clk); end loop;
    mac_enable<='0';
    assert accumulator=signed'(x"8000000000") and rounded_q15=to_signed(-32768,16) report "negative saturation mismatch" severity failure;
    report "TEST PASSED"; finish;
  end process;
  process begin wait for 30 us; assert false report "timeout" severity failure; end process;
end architecture;
