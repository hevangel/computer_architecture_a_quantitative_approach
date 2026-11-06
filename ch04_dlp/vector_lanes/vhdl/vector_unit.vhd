-- Vector functional unit with L parallel lanes (Chapter 4 / Appendix G).
-- A register file of VREGS vector registers, each MVL elements of 32 bits.  One vector
-- instruction occupies the unit for ceil(vl / L) cycles: every cycle the L lanes process the
-- next L elements (lanes whose element index is >= vl are masked off).  Doubling the lanes
-- halves the time for long vectors -- the central idea of vector machines.
--   op 0 VADD  vd = vs1 + vs2        op 3 VMULS vd = vs1 * scalar
--   op 1 VSUB  vd = vs1 - vs2        op 4 VADDS vd = vs1 + scalar
--   op 2 VMUL  vd = vs1 * vs2
-- Elements >= vl of the destination register are left unchanged.  vl must be in 1..MVL.
-- (VHDL is case-insensitive: the lane loop variable is `lane`, not `l`, to avoid the generic L.)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vector_unit is
  generic (L : positive := 4; MVL : positive := 16; VREGS : positive := 8);
  port (
    clk, rst_n : in  std_logic;
    -- element-wise register access (use only while idle)
    ld_we      : in  std_logic;
    ld_reg     : in  natural range 0 to VREGS-1;
    ld_idx     : in  natural range 0 to MVL-1;
    ld_data    : in  signed(31 downto 0);
    rd_reg     : in  natural range 0 to VREGS-1;
    rd_idx     : in  natural range 0 to MVL-1;
    rd_data    : out signed(31 downto 0);
    -- vector instruction issue
    start      : in  std_logic;
    op         : in  natural range 0 to 7;
    vd, vs1, vs2 : in natural range 0 to VREGS-1;
    scalar     : in  signed(31 downto 0);
    vl         : in  natural range 0 to MVL;
    busy       : out std_logic
  );
end entity;

architecture rtl of vector_unit is
  type vrf_t is array (0 to VREGS*MVL-1) of signed(31 downto 0);
  signal vrf : vrf_t := (others => (others => '0'));
  signal busy_i : std_logic := '0';
  signal op_q : natural range 0 to 7 := 0;
  signal vd_q, vs1_q, vs2_q : natural range 0 to VREGS-1 := 0;
  signal sc_q : signed(31 downto 0) := (others => '0');
  signal vl_q : natural range 0 to MVL := 0;
  signal pos  : natural range 0 to MVL + L := 0;               -- first element of this cycle's chunk
begin
  busy    <= busy_i;
  rd_data <= vrf(rd_reg*MVL + rd_idx);

  process (clk, rst_n)
    variable a, b, y : signed(31 downto 0);
    variable e : natural;
  begin
    if rst_n = '0' then
      busy_i <= '0';  pos <= 0;
      vrf <= (others => (others => '0'));
    elsif rising_edge(clk) then
      if busy_i = '0' then
        if ld_we = '1' then vrf(ld_reg*MVL + ld_idx) <= ld_data; end if;
        if start = '1' then
          op_q <= op;  vd_q <= vd;  vs1_q <= vs1;  vs2_q <= vs2;  sc_q <= scalar;  vl_q <= vl;
          pos <= 0;  busy_i <= '1';
        end if;
      else
        for lane in 0 to L-1 loop                               -- the L lanes work in parallel
          e := pos + lane;
          if e < vl_q then
            a := vrf(vs1_q*MVL + e);
            b := vrf(vs2_q*MVL + e);
            case op_q is
              when 0      => y := a + b;
              when 1      => y := a - b;
              when 2      => y := resize(a * b, 32);
              when 3      => y := resize(a * sc_q, 32);
              when 4      => y := a + sc_q;
              when others => y := (others => '0');
            end case;
            vrf(vd_q*MVL + e) <= y;
          end if;
        end loop;
        pos <= pos + L;
        if pos + L >= vl_q then busy_i <= '0'; end if;
      end if;
    end if;
  end process;
end architecture;
