library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_hamming_secded is end entity;

architecture sim of tb_hamming_secded is
  signal data, dec : std_logic_vector(63 downto 0) := (others => '0');
  signal code, rx  : std_logic_vector(71 downto 0) := (others => '0');
  signal sec, ded  : std_logic;
begin
  enc : entity work.secded_encoder port map (data, code);
  dcd : entity work.secded_decoder port map (rx, dec, sec, ded);

  process
    variable errors, singles, doubles : natural := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(99, 32);
    variable cw, flip : std_logic_vector(71 downto 0);
    variable dv : std_logic_vector(63 downto 0);
  begin
    for w in 0 to 11 loop
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);  dv(63 downto 32) := std_logic_vector(seed);
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);  dv(31 downto 0)  := std_logic_vector(seed);
      if w = 0 then dv := (others => '0'); end if;
      if w = 1 then dv := (others => '1'); end if;
      data <= dv;  wait for 1 ns;
      cw := code;
      rx <= cw;  wait for 1 ns;                                       -- no error
      if dec /= dv or sec = '1' or ded = '1' then errors := errors + 1; report "FAIL clean word" severity error; end if;
      for i in 0 to 71 loop                                           -- every single-bit error
        flip := cw;  flip(i) := not flip(i);
        rx <= flip;  wait for 1 ns;
        singles := singles + 1;
        if dec /= dv or sec = '0' or ded = '1' then errors := errors + 1; report "FAIL single error at " & integer'image(i) severity error; end if;
      end loop;
      for i in 0 to 71 loop                                           -- every double-bit error
        for j in i + 1 to 71 loop
          flip := cw;  flip(i) := not flip(i);  flip(j) := not flip(j);
          rx <= flip;  wait for 1 ns;
          doubles := doubles + 1;
          if sec = '1' or ded = '0' then errors := errors + 1; report "FAIL double error at " & integer'image(i) & "," & integer'image(j) severity error; end if;
        end loop;
      end loop;
    end loop;
    report integer'image(singles) & " single-bit and " & integer'image(doubles) & " double-bit error patterns checked";
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
