library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity dsp_qmac_circular_zoloop is
  port (clk,reset,mac_clear,mac_enable : in std_logic;
        sample,coefficient : in signed(15 downto 0);
        accumulator : out signed(39 downto 0); rounded_q15 : out signed(15 downto 0);
        pointer_load,pointer_step : in std_logic; pointer_start : in unsigned(3 downto 0);
        pointer_modulus : in unsigned(4 downto 0); pointer : out unsigned(3 downto 0);
        fft_index : in std_logic_vector(3 downto 0); bit_reversed : out std_logic_vector(3 downto 0);
        repeat_load,repeat_step : in std_logic; repeat_count : in unsigned(4 downto 0);
        repeat_active,repeat_last : out std_logic);
end entity;
architecture rtl of dsp_qmac_circular_zoloop is
  signal accum : signed(39 downto 0) := (others=>'0');
  signal ptr : unsigned(3 downto 0) := (others=>'0');
  signal remaining : unsigned(4 downto 0) := (others=>'0');
begin
  accumulator<=accum; pointer<=ptr;
  bit_reversed<=fft_index(0) & fft_index(1) & fft_index(2) & fft_index(3);
  repeat_active<='1' when remaining/=0 else '0';
  repeat_last<='1' when remaining=1 else '0';
  process(all)
    variable r : signed(39 downto 0);
  begin
    r:=shift_right(accum,15);
    if unsigned(accum(14 downto 0))>to_unsigned(16384,15) or
       (unsigned(accum(14 downto 0))=to_unsigned(16384,15) and r(0)='1') then r:=r+1; end if;
    if r>to_signed(32767,40) then rounded_q15<=to_signed(32767,16);
    elsif r<to_signed(-32768,40) then rounded_q15<=to_signed(-32768,16);
    else rounded_q15<=r(15 downto 0); end if;
  end process;
  process(clk)
    variable product : signed(31 downto 0);
    variable sum : signed(40 downto 0);
    constant max_acc : signed(39 downto 0) := x"7fffffffff";
    constant min_acc : signed(39 downto 0) := x"8000000000";
  begin
    if rising_edge(clk) then
      if reset='1' then accum<=(others=>'0'); ptr<=(others=>'0'); remaining<=(others=>'0');
      else
        if mac_clear='1' then accum<=(others=>'0');
        elsif mac_enable='1' then
          product:=sample*coefficient; sum:=resize(accum,41)+resize(product,41);
          if sum>resize(max_acc,41) then accum<=max_acc;
          elsif sum<resize(min_acc,41) then accum<=min_acc;
          else accum<=sum(39 downto 0); end if;
        end if;
        if pointer_load='1' then ptr<=pointer_start;
        elsif pointer_step='1' and pointer_modulus/=0 and pointer_modulus<=16 then
          if resize(ptr,5)+1>=pointer_modulus then ptr<=(others=>'0'); else ptr<=ptr+1; end if;
        end if;
        if repeat_load='1' then remaining<=repeat_count;
        elsif repeat_step='1' and remaining/=0 then remaining<=remaining-1; end if;
      end if;
    end if;
  end process;
end architecture;
