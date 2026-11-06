-- RAID-5 parity arithmetic for one stripe (Appendix D).  Parity is the XOR of the data blocks,
-- so XOR-ing *all* blocks of a healthy stripe gives zero, and the XOR of the survivors
-- reconstructs a failed disk.  A small write need not read the whole stripe:
--     new_parity = old_parity xor old_data xor new_data
library ieee;
use ieee.std_logic_1164.all;

entity raid5_parity is
  generic (DISKS : positive := 5;      -- total disks in the stripe (DISKS-1 data + 1 parity)
           W     : positive := 32);    -- block width in bits
  port (
    data_blocks : in  std_logic_vector((DISKS-1)*W-1 downto 0);
    parity_out  : out std_logic_vector(W-1 downto 0);
    stripe      : in  std_logic_vector(DISKS*W-1 downto 0);
    failed      : in  natural range 0 to DISKS-1;
    syndrome    : out std_logic_vector(W-1 downto 0);      -- 0 for a consistent stripe
    rebuilt     : out std_logic_vector(W-1 downto 0);      -- contents of disk `failed`
    old_data, new_data, old_parity : in  std_logic_vector(W-1 downto 0);
    new_parity  : out std_logic_vector(W-1 downto 0)
  );
end entity;

architecture rtl of raid5_parity is
begin
  process (all)
    variable par, syn, reb : std_logic_vector(W-1 downto 0);
  begin
    par := (others => '0');
    for i in 0 to DISKS-2 loop par := par xor data_blocks(i*W + W-1 downto i*W); end loop;
    parity_out <= par;
    syn := (others => '0');  reb := (others => '0');
    for i in 0 to DISKS-1 loop
      syn := syn xor stripe(i*W + W-1 downto i*W);
      if i /= failed then reb := reb xor stripe(i*W + W-1 downto i*W); end if;
    end loop;
    syndrome <= syn;  rebuilt <= reb;
    new_parity <= old_parity xor old_data xor new_data;
  end process;
end architecture;
