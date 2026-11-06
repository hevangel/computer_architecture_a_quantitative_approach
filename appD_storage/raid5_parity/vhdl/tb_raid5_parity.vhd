library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_raid5_parity is end entity;

architecture sim of tb_raid5_parity is
  constant DISKS : positive := 5;
  constant W     : positive := 32;
  signal data_blocks : std_logic_vector((DISKS-1)*W-1 downto 0) := (others => '0');
  signal parity_out, syndrome, rebuilt, old_data, new_data, old_parity, new_parity : std_logic_vector(W-1 downto 0) := (others => '0');
  signal stripe : std_logic_vector(DISKS*W-1 downto 0) := (others => '0');
  signal failed : natural range 0 to DISKS-1 := 0;
begin
  dut : entity work.raid5_parity
    generic map (DISKS, W)
    port map (data_blocks, parity_out, stripe, failed, syndrome, rebuilt, old_data, new_data, old_parity, new_parity);

  process
    variable errors : natural := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(2024, 32);
    impure function rnd return std_logic_vector is
    begin
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
      return std_logic_vector(seed);
    end function;
    variable db : std_logic_vector((DISKS-1)*W-1 downto 0);
    variable st : std_logic_vector(DISKS*W-1 downto 0);
    variable nd : std_logic_vector(W-1 downto 0);
  begin
    for t in 0 to 199 loop
      for i in 0 to DISKS-2 loop db(i*W + W-1 downto i*W) := rnd; end loop;
      data_blocks <= db;  wait for 1 ns;
      st := parity_out & db;                                    -- parity lives on the last disk
      stripe <= st;
      for f in 0 to DISKS-1 loop
        failed <= f;  wait for 1 ns;
        if syndrome /= (syndrome'range => '0') then errors := errors + 1; report "FAIL: healthy stripe has nonzero syndrome" severity error; end if;
        if rebuilt /= st(f*W + W-1 downto f*W) then errors := errors + 1; report "FAIL: rebuild of disk " & integer'image(f) severity error; end if;
      end loop;
      -- small write to data disk 2
      nd := rnd;
      old_data <= db(2*W + W-1 downto 2*W);  new_data <= nd;  old_parity <= parity_out;  wait for 1 ns;
      db(2*W + W-1 downto 2*W) := nd;
      data_blocks <= db;  wait for 1 ns;
      if new_parity /= parity_out then errors := errors + 1; report "FAIL: small-write parity" severity error; end if;
    end loop;
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
