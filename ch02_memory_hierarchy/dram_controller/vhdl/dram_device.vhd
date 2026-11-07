-- A behavioural DRAM device with an independent TIMING CHECKER (Chapter 2: DRAM organisation and timing).
--
-- Geometry: 4 banks x 16 rows x 4 bursts per row; one burst = BL beats of 32 bits (128 bits here, moved by one RD/WR command).  The burst address used by the
-- controller is (row(3:0), bank(1:0), col(1:0)).  Each bank has a ROW BUFFER: ACT copies a row into it, RD/WR access the open row, PRE closes it.
--
-- Commands (cmd_valid with cmd): 1 ACT(bank,row)  2 RD(bank,col)  3 WR(bank,col,wdata)  4 PRE(bank)  5 REF (all banks must be precharged).
-- A RD at command cycle r returns its burst in the single cycle r + tCL + BL (rd_valid, rd_data): beats occupy r+tCL .. r+tCL+BL-1.  A WR stores its data at once
-- (the write latency tCWL only matters for the timing constraints that follow it).
--
-- The checker keeps a timestamp of every command and flags -- with a report and the sticky `violation` bit -- anything that breaks a constraint or the protocol:
--   ACT: bank idle;  >= tRP after PRE of that bank;  >= tRFC after REF;  >= tRRD after any ACT
--   RD/WR: bank active;  >= tRCD after ACT;  >= tCCD after any column command;  RD >= tWTR after write data;  WR >= tRTW after a RD
--   PRE: bank active;  >= tRAS after ACT;  >= tRTP after RD;  >= tWR after write data
--   REF: all banks idle and >= tRP after their PRE.   It also records the longest gap between refreshes.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dram_device is
  generic (BL : natural := 4; tRCD : natural := 3; tCL : natural := 3; tCWL : natural := 2; tRP : natural := 3; tRAS : natural := 7;
           tWR : natural := 3; tRTP : natural := 2; tRRD : natural := 2; tCCD : natural := 4; tWTR : natural := 3; tRTW : natural := 6; tRFC : natural := 12);
  port (
    clk, rst_n  : in  std_logic;
    cmd_valid   : in  std_logic;
    cmd         : in  natural range 0 to 7;
    cmd_bank    : in  natural range 0 to 3;
    cmd_row     : in  natural range 0 to 15;
    cmd_col     : in  natural range 0 to 3;
    cmd_wdata   : in  std_logic_vector(127 downto 0);
    rd_valid    : out std_logic;
    rd_data     : out std_logic_vector(127 downto 0);
    violation   : out std_logic;                       -- sticky
    stat_refs   : out natural;
    max_ref_gap : out natural                          -- longest interval between two REF commands (cycles)
  );
end entity;

architecture rtl of dram_device is
  constant NEVER : integer := -1000000;
  subtype burst_t is std_logic_vector(127 downto 0);
  type mem_t is array (0 to 255) of burst_t;
  type int_arr is array (0 to 3) of integer;
  type nat_arr is array (0 to 3) of natural;
  type burst_arr is array (0 to 3) of burst_t;

  function init_burst(a : natural) return burst_t is
    variable r : burst_t;
  begin
    for k in 0 to 3 loop
      r(32*k + 31 downto 32*k) := std_logic_vector(unsigned'(x"D0000000") or shift_left(to_unsigned(a, 32), 8) or to_unsigned(k, 32));
    end loop;
    return r;
  end function;
  function init_mem return mem_t is
    variable m : mem_t;
  begin
    for a in 0 to 255 loop m(a) := init_burst(a); end loop;
    return m;
  end function;

  signal mem : mem_t := init_mem;
  signal active : std_logic_vector(0 to 3) := (others => '0');
  signal orow : nat_arr := (others => 0);
  signal last_act, last_pre, last_rd_b, last_wr_end_b : int_arr := (others => NEVER);
  signal last_act_any, last_col_any, last_ref, last_rd_any, last_wr_end_any : integer := NEVER;
  signal tnow : integer := 0;
  signal rd_cnt : nat_arr := (others => 0);
  signal rd_dat : burst_arr := (others => (others => '0'));
  signal viol : std_logic := '0';
  signal refs, gap : natural := 0;
begin
  violation <= viol;  stat_refs <= refs;  max_ref_gap <= gap;
  rd_valid <= '1' when rd_cnt(0) = 1 or rd_cnt(1) = 1 or rd_cnt(2) = 1 or rd_cnt(3) = 1 else '0';
  process (all)
  begin
    rd_data <= (others => '0');
    for s in 0 to 3 loop if rd_cnt(s) = 1 then rd_data <= rd_dat(s); end if; end loop;
  end process;

  process (clk, rst_n)
    variable taken : boolean;
    variable b : natural range 0 to 3;
    variable idx : natural;
    procedure fail(msg : string) is
    begin
      viol <= '1';
      report "DRAM VIOLATION at cycle " & integer'image(tnow) & ": " & msg severity error;
    end procedure;
  begin
    if rst_n = '0' then
      viol <= '0';  refs <= 0;  gap <= 0;  tnow <= 0;
      last_act_any <= NEVER;  last_col_any <= NEVER;  last_ref <= NEVER;  last_rd_any <= NEVER;  last_wr_end_any <= NEVER;
      active <= (others => '0');  orow <= (others => 0);  last_act <= (others => NEVER);  last_pre <= (others => NEVER);
      last_rd_b <= (others => NEVER);  last_wr_end_b <= (others => NEVER);  rd_cnt <= (others => 0);  rd_dat <= (others => (others => '0'));
      mem <= init_mem;
    elsif rising_edge(clk) then
      tnow <= tnow + 1;
      for s in 0 to 3 loop if rd_cnt(s) /= 0 then rd_cnt(s) <= rd_cnt(s) - 1; end if; end loop;
      if cmd_valid = '1' then
        b := cmd_bank;
        case cmd is
          when 1 =>                                                                          -- ACT
            if active(b) = '1'                    then fail("ACT to a bank with an open row"); end if;
            if tnow - last_pre(b) < tRP           then fail("ACT before tRP after PRE"); end if;
            if tnow - last_ref < tRFC             then fail("ACT before tRFC after REF"); end if;
            if tnow - last_act_any < tRRD         then fail("ACT before tRRD after another ACT"); end if;
            active(b) <= '1';  orow(b) <= cmd_row;  last_act(b) <= tnow;  last_act_any <= tnow;
          when 2 | 3 =>                                                                      -- RD / WR
            if active(b) = '0'                    then fail("column command to a closed bank"); end if;
            if tnow - last_act(b) < tRCD          then fail("column command before tRCD after ACT"); end if;
            if tnow - last_col_any < tCCD         then fail("column commands closer than tCCD"); end if;
            if cmd = 2 and tnow - last_wr_end_any < tWTR then fail("RD before tWTR after write data"); end if;
            if cmd = 3 and tnow - last_rd_any < tRTW     then fail("WR before tRTW after a RD"); end if;
            last_col_any <= tnow;
            idx := orow(b) * 16 + b * 4 + cmd_col;
            if cmd = 2 then
              last_rd_b(b) <= tnow;  last_rd_any <= tnow;
              taken := false;                                                                 -- take a slot that is free or finishing this cycle
              for s in 0 to 3 loop
                if not taken and (rd_cnt(s) = 0 or rd_cnt(s) = 1) then rd_cnt(s) <= tCL + BL;  rd_dat(s) <= mem(idx);  taken := true; end if;
              end loop;
            else
              mem(idx) <= cmd_wdata;
              last_wr_end_b(b) <= tnow + tCWL + BL;  last_wr_end_any <= tnow + tCWL + BL;
            end if;
          when 4 =>                                                                          -- PRE
            if active(b) = '0'                    then fail("PRE to a closed bank"); end if;
            if tnow - last_act(b) < tRAS          then fail("PRE before tRAS after ACT"); end if;
            if tnow - last_rd_b(b) < tRTP         then fail("PRE before tRTP after RD"); end if;
            if tnow - last_wr_end_b(b) < tWR      then fail("PRE before tWR after write data"); end if;
            active(b) <= '0';  last_pre(b) <= tnow;
          when 5 =>                                                                          -- REF
            for k in 0 to 3 loop
              if active(k) = '1'                  then fail("REF with an open bank"); end if;
              if tnow - last_pre(k) < tRP         then fail("REF before tRP after PRE"); end if;
            end loop;
            if tnow - last_ref < tRFC             then fail("REF before tRFC after the previous REF"); end if;
            if last_ref /= NEVER and tnow - last_ref > gap then gap <= tnow - last_ref; end if;
            last_ref <= tnow;  refs <= refs + 1;
          when others => null;
        end case;
      end if;
    end if;
  end process;
end architecture;
