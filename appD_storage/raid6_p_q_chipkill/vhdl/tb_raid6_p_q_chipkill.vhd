library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_raid6_p_q_chipkill is end entity;
architecture tb of tb_raid6_p_q_chipkill is
  signal data_in,symbols_in : std_logic_vector(31 downto 0) := (others=>'0');
  signal encoded,stripe_in,recovered : std_logic_vector(47 downto 0) := (others=>'0');
  signal erased : std_logic_vector(5 downto 0) := (others=>'0');
  signal recover_valid : std_logic;
  signal symbol_encoded,symbol_received,symbol_corrected : std_logic_vector(39 downto 0) := (others=>'0');
  signal symbol_valid : std_logic;
  signal symbol_error_position : std_logic_vector(3 downto 0);
begin
  dut: entity work.raid6_p_q_chipkill port map (data_in,encoded,stripe_in,erased,recovered,recover_valid,
     symbols_in,symbol_encoded,symbol_received,symbol_corrected,symbol_valid,symbol_error_position);
  process
    file vectors : text open read_mode is "../../../../appD_storage/raid6_p_q_chipkill/golden.txt";
    variable line_in : line;
    variable word : std_logic_vector(31 downto 0);
    variable expected_stripe, damaged : std_logic_vector(47 downto 0);
    variable expected_symbols, corrupted : std_logic_vector(39 downto 0);
    variable mask_bits : std_logic_vector(5 downto 0);
    variable n, cases : integer := 0;
  begin
    while not endfile(vectors) loop
      readline(vectors,line_in); hread(line_in,word); hread(line_in,expected_stripe); hread(line_in,expected_symbols);
      data_in<=word; symbols_in<=word; wait for 1 ns;
      assert encoded=expected_stripe and symbol_encoded=expected_symbols report "encoding mismatch" severity failure;
      for mask in 0 to 63 loop
        mask_bits:=std_logic_vector(to_unsigned(mask,6)); n:=0; damaged:=expected_stripe;
        for i in 0 to 5 loop
          if mask_bits(i)='1' then n:=n+1; damaged(i*8+7 downto i*8):=x"a5"; end if;
        end loop;
        erased<=mask_bits; stripe_in<=damaged; wait for 1 ns;
        if n<=2 then assert recover_valid='1' and recovered=expected_stripe report "recovery mismatch" severity failure;
        else assert recover_valid='0' report "invalid mask accepted" severity failure; end if;
      end loop;
      symbol_received<=expected_symbols; wait for 1 ns;
      assert symbol_valid='1' and symbol_error_position=x"f" and symbol_corrected=expected_symbols
        report "clean symbol mismatch" severity failure;
      for pos in 0 to 9 loop
        for err in 1 to 15 loop
          corrupted:=expected_symbols;
          corrupted(pos*4+3 downto pos*4):=expected_symbols(pos*4+3 downto pos*4) xor std_logic_vector(to_unsigned(err,4));
          symbol_received<=corrupted; wait for 1 ns;
          assert symbol_valid='1' and symbol_error_position=std_logic_vector(to_unsigned(pos,4)) and symbol_corrected=expected_symbols
            report "symbol mismatch" severity failure;
        end loop;
      end loop;
      cases:=cases+1;
    end loop;
    assert cases=36 report "unexpected vector count" severity failure;
    report "TEST PASSED 36 vectors"; finish;
  end process;
end architecture;
