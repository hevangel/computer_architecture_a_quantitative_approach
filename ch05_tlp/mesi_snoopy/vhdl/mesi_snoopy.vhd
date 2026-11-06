-- MESI write-invalidate snooping coherence for P private caches sharing one bus (Chapter 5).
-- The model tracks a single cache line (one word) -- enough to show every protocol transition.
-- One CPU operation is performed atomically per clock when op_valid is high; the bus
-- transaction, supplied data and write-back are visible combinationally in that cycle.
--
--   state   meaning                          encoding on state_out
--   I       invalid                          00
--   S       shared, clean                    01
--   E       exclusive, clean (silent write)  10
--   M       modified, dirty, only copy       11
--   bus_txn: 00 none | 01 BusRd | 10 BusRdX | 11 BusUpgr
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mesi_snoopy is
  generic (P : positive := 4; DATA_W : positive := 32);
  port (
    clk, rst_n : in  std_logic;
    op_valid   : in  std_logic;
    op_core    : in  natural range 0 to P-1;
    op_write   : in  std_logic;
    op_wdata   : in  std_logic_vector(DATA_W-1 downto 0);
    rdata      : out std_logic_vector(DATA_W-1 downto 0);
    bus_txn    : out std_logic_vector(1 downto 0);
    writeback  : out std_logic;
    state_out  : out std_logic_vector(2*P-1 downto 0);
    mem_out    : out std_logic_vector(DATA_W-1 downto 0)
  );
end entity;

architecture rtl of mesi_snoopy is
  type mesi_t is (ST_I, ST_S, ST_E, ST_M);
  type st_arr   is array (0 to P-1) of mesi_t;
  type data_arr is array (0 to P-1) of std_logic_vector(DATA_W-1 downto 0);
  signal st    : st_arr   := (others => ST_I);
  signal data  : data_arr := (others => (others => '0'));
  signal mem   : std_logic_vector(DATA_W-1 downto 0) := (others => '0');
  signal nst   : st_arr;
  signal ndata : data_arr;
  signal nmem  : std_logic_vector(DATA_W-1 downto 0);

  function encode(s : mesi_t) return std_logic_vector is
  begin
    case s is
      when ST_I => return "00";
      when ST_S => return "01";
      when ST_E => return "10";
      when ST_M => return "11";
    end case;
  end function;
begin
  comb : process (all)
    variable c, owner : natural;
    variable have_owner, other_valid : boolean;
    variable v_nst : st_arr;
    variable v_nd  : data_arr;
    variable v_mem, v_rd : std_logic_vector(DATA_W-1 downto 0);
    variable v_txn : std_logic_vector(1 downto 0);
    variable v_wb  : std_logic;
  begin
    c := op_core;
    v_nst := st;  v_nd := data;  v_mem := mem;  v_txn := "00";  v_wb := '0';  v_rd := data(c);
    owner := 0;  have_owner := false;  other_valid := false;
    for j in 0 to P-1 loop
      if j /= c then
        if st(j) /= ST_I then other_valid := true; end if;
        if st(j) = ST_M or st(j) = ST_E then owner := j; have_owner := true; end if;
      end if;
    end loop;

    if op_valid = '1' then
      if op_write = '0' then
        if st(c) = ST_I then                                    -- read miss: BusRd
          v_txn := "01";
          if have_owner then
            v_rd := data(owner);
            if st(owner) = ST_M then v_mem := data(owner); v_wb := '1'; end if;
            v_nst(owner) := ST_S;
          else
            v_rd := mem;
          end if;
          v_nd(c) := v_rd;
          if other_valid then v_nst(c) := ST_S; else v_nst(c) := ST_E; end if;
          for j in 0 to P-1 loop
            if j /= c and st(j) = ST_E then v_nst(j) := ST_S; end if;
          end loop;
        end if;                                                  -- read hit: no change
      else
        case st(c) is
          when ST_M => null;                                     -- write hit, already owned
          when ST_E => v_nst(c) := ST_M;                         -- silent upgrade: no bus traffic
          when ST_S =>                                           -- BusUpgr: invalidate other sharers
            v_txn := "11";
            for j in 0 to P-1 loop if j /= c then v_nst(j) := ST_I; end if; end loop;
            v_nst(c) := ST_M;
          when ST_I =>                                           -- BusRdX: fetch with intent to modify
            v_txn := "10";
            if have_owner and st(owner) = ST_M then v_mem := data(owner); v_wb := '1'; end if;
            for j in 0 to P-1 loop if j /= c then v_nst(j) := ST_I; end if; end loop;
            v_nst(c) := ST_M;
        end case;
        v_nd(c) := op_wdata;
      end if;
    end if;
    nst <= v_nst;  ndata <= v_nd;  nmem <= v_mem;
    rdata <= v_rd;  bus_txn <= v_txn;  writeback <= v_wb;
  end process;

  outs : process (all)
  begin
    for j in 0 to P-1 loop state_out(2*j + 1 downto 2*j) <= encode(st(j)); end loop;
    mem_out <= mem;
  end process;

  seq : process (clk, rst_n)
  begin
    if rst_n = '0' then
      st <= (others => ST_I);  data <= (others => (others => '0'));  mem <= (others => '0');
    elsif rising_edge(clk) then
      if op_valid = '1' then st <= nst; data <= ndata; mem <= nmem; end if;
    end if;
  end process;
end architecture;
