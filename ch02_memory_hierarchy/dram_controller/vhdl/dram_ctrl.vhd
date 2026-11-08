-- A DRAM memory controller (Chapter 2: memory technology and organisation; Appendix B on DRAM timing).
--
-- A request queue feeds a command scheduler that drives ONE command per cycle to a 4-bank DRAM (see dram_device).  The controller:
--   * tracks the open row of every bank (the ROW BUFFER) and the timing constraints between commands with down-counters:
--         tRCD (ACT->RD/WR)  tRAS (ACT->PRE)  tRP (PRE->ACT)  tRTP (RD->PRE)  tWR (write data->PRE)  tRRD (ACT->ACT)
--         tCCD (column->column)  tWTR (write data->RD)  tRTW (RD->WR)  tRFC (REF->ACT)  and REFRESH every tREFI;
--   * SCHEDULES either FCFS (only the oldest request may make progress) or FR-FCFS ("first-ready, first-come-first-served"): among the requests whose next
--     command can issue, row-buffer HITS go first, then the oldest request; a row is not closed while a queued request still hits it;
--   * never reorders two requests to the same burst address (read-after-write etc. keep program order);
--   * applies an OPEN-page policy (leave the row open until a conflict or a refresh) or a CLOSED-page policy (precharge a bank as soon as nothing queued hits its row);
--   * every tREFI cycles stops new work, precharges the open banks, issues REF, and resumes after tRFC.
-- Requests are one burst (128 bits) at a burst address (row(3:0), bank(1:0), col(1:0)).  Reads answer on rd_resp_* when the data arrives; writes answer on wr_resp_*
-- (tCWL + BL cycles after the WR command).  Latencies, request accepted at cycle q (idle controller, constraints long satisfied):
--     row hit   : q + 2 + tCL + BL                     row miss (bank closed): q + 2 + tRCD + tCL + BL        row conflict: q + 2 + tRP + tRCD + tCL + BL
-- (the "2" is the pipeline: queue write, command decision, registered command output).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dram_ctrl is
  generic (QD : positive := 8; BL : natural := 4;
           tRCD : natural := 3; tCL : natural := 3; tCWL : natural := 2; tRP : natural := 3; tRAS : natural := 7;
           tWR : natural := 3; tRTP : natural := 2; tRRD : natural := 2; tCCD : natural := 4; tWTR : natural := 3;
           tRTW : natural := 6; tRFC : natural := 12; tREFI : natural := 200;
           FR_FCFS : boolean := true; OPEN_PAGE : boolean := true);
  port (
    clk, rst_n    : in  std_logic;
    -- requests
    req_valid     : in  std_logic;
    req_ready     : out std_logic;
    req_write     : in  std_logic;
    req_addr      : in  std_logic_vector(7 downto 0);
    req_wdata     : in  std_logic_vector(127 downto 0);
    req_id        : in  natural range 0 to 63;
    -- responses
    rd_resp_valid : out std_logic;
    rd_resp_id    : out natural range 0 to 63;
    rd_resp_data  : out std_logic_vector(127 downto 0);
    wr_resp_valid : out std_logic;
    wr_resp_id    : out natural range 0 to 63;
    -- DRAM command bus
    cmd_valid     : out std_logic;
    cmd           : out natural range 0 to 7;
    cmd_bank      : out natural range 0 to 3;
    cmd_row       : out natural range 0 to 15;
    cmd_col       : out natural range 0 to 3;
    cmd_wdata     : out std_logic_vector(127 downto 0);
    dev_rd_valid  : in  std_logic;
    dev_rd_data   : in  std_logic_vector(127 downto 0);
    stat_act, stat_pre, stat_rd, stat_wr, stat_ref : out natural
  );
end entity;

architecture rtl of dram_ctrl is
  constant K_ACT : natural := 1;  constant K_RD : natural := 2;  constant K_WR : natural := 3;  constant K_PRE : natural := 4;  constant K_REF : natural := 5;
  subtype burst_t is std_logic_vector(127 downto 0);
  type addr_arr  is array (0 to QD-1) of std_logic_vector(7 downto 0);
  type burst_arr is array (0 to QD-1) of burst_t;
  type nat_q     is array (0 to QD-1) of natural;
  type nat_4     is array (0 to 3) of natural;

  -- request queue
  signal q_valid, q_write : std_logic_vector(0 to QD-1) := (others => '0');
  signal q_addr : addr_arr := (others => (others => '0'));
  signal q_wdata : burst_arr := (others => (others => '0'));
  signal q_id, q_seq : nat_q := (others => 0);
  signal seq_ctr : natural := 0;
  -- bank state and timing counters (a command is allowed when its counter is 0)
  signal b_open : std_logic_vector(0 to 3) := (others => '0');
  signal b_row, c_col, c_pre, c_act : nat_4 := (others => 0);
  signal c_ccd, c_rrd, c_wtr, c_rtw, refi_cnt : natural := 0;
  signal ref_pending : std_logic := '0';
  -- in-flight responses
  signal rid, w_cnt, w_id : nat_4 := (others => 0);
  signal r_head, r_tail : natural range 0 to 3 := 0;
  -- statistics
  signal n_act, n_pre, n_rd, n_wr, n_ref : natural := 0;
  -- scheduler results
  signal free_v : boolean;
  signal free_idx : natural range 0 to QD-1;
  signal have_cmd, sel_is_col : boolean;
  signal sel_cmd, sel_bank, sel_row, sel_col, sel_idx : natural;
  signal ready_i : std_logic;
  -- registered command outputs
  signal cmd_valid_i : std_logic := '0';
  signal cmd_i, cmd_bank_i, cmd_row_i, cmd_col_i : natural := 0;
  signal cmd_wdata_i : burst_t := (others => '0');

  function max_n(x, y : natural) return natural is begin if x > y then return x; else return y; end if; end function;
  function dec(x : natural) return natural is begin if x > 0 then return x - 1; else return 0; end if; end function;
begin
  req_ready <= ready_i;
  cmd_valid <= cmd_valid_i;  cmd <= cmd_i;  cmd_bank <= cmd_bank_i;  cmd_row <= cmd_row_i;  cmd_col <= cmd_col_i;  cmd_wdata <= cmd_wdata_i;
  stat_act <= n_act;  stat_pre <= n_pre;  stat_rd <= n_rd;  stat_wr <= n_wr;  stat_ref <= n_ref;

  -- ---- scheduler (combinational) ------------------------------------------------------------------------------
  sched : process (all)
    variable fv : boolean;  variable fi : natural range 0 to QD-1;
    variable col_found, oth_found, hz, is_old, hit, col_ok, act_ok, pre_ok, other_hit, elig, hit_pending, any_open, pre_found : boolean;
    variable col_seq, oth_seq, col_idx, oth_idx, oth_cmd, bb, rr, pre_bank : natural;
    variable hc : boolean;  variable s_cmd, s_bank, s_row, s_col, s_idx : natural;  variable s_col_cmd : boolean;
  begin
    fv := false;  fi := 0;
    for i in QD - 1 downto 0 loop if q_valid(i) = '0' then fv := true; fi := i; end if; end loop;
    free_v <= fv;  free_idx <= fi;
    if fv then ready_i <= '1'; else ready_i <= '0'; end if;

    col_found := false;  oth_found := false;  col_seq := natural'high;  oth_seq := natural'high;  col_idx := 0;  oth_idx := 0;  oth_cmd := 0;
    for i in 0 to QD - 1 loop
      if q_valid(i) = '1' then
        bb := to_integer(unsigned(q_addr(i)(3 downto 2)));  rr := to_integer(unsigned(q_addr(i)(7 downto 4)));
        hz := false;  is_old := true;
        for j in 0 to QD - 1 loop
          if q_valid(j) = '1' and q_seq(j) < q_seq(i) then
            is_old := false;
            if q_addr(j) = q_addr(i) then hz := true; end if;                                  -- an older request to the same burst: keep program order
          end if;
        end loop;
        if FR_FCFS then elig := not hz; else elig := is_old; end if;
        hit := b_open(bb) = '1' and b_row(bb) = rr;
        col_ok := hit and c_col(bb) = 0 and c_ccd = 0 and ((q_write(i) = '1' and c_rtw = 0) or (q_write(i) = '0' and c_wtr = 0));
        act_ok := b_open(bb) = '0' and c_act(bb) = 0 and c_rrd = 0;
        other_hit := false;                                                                     -- does any queued request still hit the open row of this bank?
        for k in 0 to QD - 1 loop
          if q_valid(k) = '1' and to_integer(unsigned(q_addr(k)(3 downto 2))) = bb and b_open(bb) = '1' and b_row(bb) = to_integer(unsigned(q_addr(k)(7 downto 4))) then other_hit := true; end if;
        end loop;
        pre_ok := b_open(bb) = '1' and b_row(bb) /= rr and c_pre(bb) = 0 and ((not FR_FCFS) or (not other_hit));
        if elig and col_ok and q_seq(i) < col_seq then col_found := true; col_seq := q_seq(i); col_idx := i; end if;
        if elig and (act_ok or pre_ok) and q_seq(i) < oth_seq then
          oth_found := true;  oth_seq := q_seq(i);  oth_idx := i;
          if act_ok then oth_cmd := K_ACT; else oth_cmd := K_PRE; end if;
        end if;
      end if;
    end loop;

    -- closed-page / refresh helpers
    any_open := false;  pre_found := false;  pre_bank := 0;
    for b in 3 downto 0 loop
      if b_open(b) = '1' then any_open := true; end if;
      hit_pending := false;
      for k in 0 to QD - 1 loop
        if q_valid(k) = '1' and to_integer(unsigned(q_addr(k)(3 downto 2))) = b and b_row(b) = to_integer(unsigned(q_addr(k)(7 downto 4))) then hit_pending := true; end if;
      end loop;
      if b_open(b) = '1' and c_pre(b) = 0 and (ref_pending = '1' or ((not OPEN_PAGE) and (not hit_pending))) then pre_found := true; pre_bank := b; end if;
    end loop;

    -- pick the command
    hc := false;  s_cmd := 0;  s_bank := 0;  s_row := 0;  s_col := 0;  s_idx := 0;  s_col_cmd := false;
    if ref_pending = '1' then
      if pre_found then hc := true; s_cmd := K_PRE; s_bank := pre_bank;
      elsif (not any_open) and c_act(0) = 0 and c_act(1) = 0 and c_act(2) = 0 and c_act(3) = 0 then hc := true; s_cmd := K_REF;
      end if;
    elsif col_found then
      hc := true;  s_idx := col_idx;  s_col_cmd := true;
      if q_write(col_idx) = '1' then s_cmd := K_WR; else s_cmd := K_RD; end if;
      s_bank := to_integer(unsigned(q_addr(col_idx)(3 downto 2)));  s_row := to_integer(unsigned(q_addr(col_idx)(7 downto 4)));  s_col := to_integer(unsigned(q_addr(col_idx)(1 downto 0)));
    elsif oth_found then
      hc := true;  s_idx := oth_idx;  s_cmd := oth_cmd;
      s_bank := to_integer(unsigned(q_addr(oth_idx)(3 downto 2)));  s_row := to_integer(unsigned(q_addr(oth_idx)(7 downto 4)));  s_col := to_integer(unsigned(q_addr(oth_idx)(1 downto 0)));
      if oth_cmd = K_PRE then s_row := b_row(s_bank); end if;
    elsif pre_found then                                                                         -- closed-page: close an idle open bank
      hc := true;  s_cmd := K_PRE;  s_bank := pre_bank;
    end if;
    have_cmd <= hc;  sel_cmd <= s_cmd;  sel_bank <= s_bank;  sel_row <= s_row;  sel_col <= s_col;  sel_idx <= s_idx;  sel_is_col <= s_col_cmd;
  end process;

  -- ---- responses -------------------------------------------------------------------------------------------------
  rd_resp_valid <= dev_rd_valid;  rd_resp_id <= rid(r_head);  rd_resp_data <= dev_rd_data;
  wresp : process (all)
  begin
    wr_resp_valid <= '0';  wr_resp_id <= 0;
    for s in 0 to 3 loop if w_cnt(s) = 1 then wr_resp_valid <= '1'; wr_resp_id <= w_id(s); end if; end loop;
  end process;

  seq : process (clk, rst_n)
    variable taken : boolean;
  begin
    if rst_n = '0' then
      cmd_valid_i <= '0';  cmd_i <= 0;  cmd_bank_i <= 0;  cmd_row_i <= 0;  cmd_col_i <= 0;  cmd_wdata_i <= (others => '0');
      seq_ctr <= 0;  refi_cnt <= 0;  ref_pending <= '0';  c_ccd <= 0;  c_rrd <= 0;  c_wtr <= 0;  c_rtw <= 0;
      r_head <= 0;  r_tail <= 0;
      n_act <= 0;  n_pre <= 0;  n_rd <= 0;  n_wr <= 0;  n_ref <= 0;
      q_valid <= (others => '0');  q_write <= (others => '0');  q_addr <= (others => (others => '0'));  q_wdata <= (others => (others => '0'));
      q_id <= (others => 0);  q_seq <= (others => 0);
      b_open <= (others => '0');  b_row <= (others => 0);  c_col <= (others => 0);  c_pre <= (others => 0);  c_act <= (others => 0);
      rid <= (others => 0);  w_cnt <= (others => 0);  w_id <= (others => 0);
    elsif rising_edge(clk) then
      -- counters tick down
      for b in 0 to 3 loop
        c_col(b) <= dec(c_col(b));  c_pre(b) <= dec(c_pre(b));  c_act(b) <= dec(c_act(b));  w_cnt(b) <= dec(w_cnt(b));
      end loop;
      c_ccd <= dec(c_ccd);  c_rrd <= dec(c_rrd);  c_wtr <= dec(c_wtr);  c_rtw <= dec(c_rtw);
      -- refresh timer
      if refi_cnt >= tREFI then ref_pending <= '1'; else refi_cnt <= refi_cnt + 1; end if;
      if dev_rd_valid = '1' then
        if r_head = 3 then r_head <= 0; else r_head <= r_head + 1; end if;
      end if;

      -- enqueue
      if req_valid = '1' and ready_i = '1' then
        q_valid(free_idx) <= '1';  q_write(free_idx) <= req_write;  q_addr(free_idx) <= req_addr;
        q_wdata(free_idx) <= req_wdata;  q_id(free_idx) <= req_id;  q_seq(free_idx) <= seq_ctr;  seq_ctr <= seq_ctr + 1;
      end if;

      -- command issue
      if have_cmd then cmd_valid_i <= '1'; else cmd_valid_i <= '0'; end if;
      cmd_i <= sel_cmd;  cmd_bank_i <= sel_bank;  cmd_row_i <= sel_row;  cmd_col_i <= sel_col;
      if sel_is_col then cmd_wdata_i <= q_wdata(sel_idx); else cmd_wdata_i <= (others => '0'); end if;
      if have_cmd then
        case sel_cmd is
          when K_ACT =>
            b_open(sel_bank) <= '1';  b_row(sel_bank) <= sel_row;
            c_col(sel_bank) <= tRCD - 1;  c_pre(sel_bank) <= tRAS - 1;  c_rrd <= tRRD - 1;
            n_act <= n_act + 1;
          when K_RD =>
            c_ccd <= tCCD - 1;  c_rtw <= tRTW - 1;  c_pre(sel_bank) <= max_n(dec(c_pre(sel_bank)), tRTP - 1);
            rid(r_tail) <= q_id(sel_idx);  if r_tail = 3 then r_tail <= 0; else r_tail <= r_tail + 1; end if;
            q_valid(sel_idx) <= '0';  n_rd <= n_rd + 1;
          when K_WR =>
            c_ccd <= tCCD - 1;  c_wtr <= tCWL + BL + tWTR - 1;
            c_pre(sel_bank) <= max_n(dec(c_pre(sel_bank)), tCWL + BL + tWR - 1);
            q_valid(sel_idx) <= '0';  n_wr <= n_wr + 1;
            taken := false;
            for s in 0 to 3 loop
              if not taken and (w_cnt(s) = 0 or w_cnt(s) = 1) then w_cnt(s) <= tCWL + BL + 1;  w_id(s) <= q_id(sel_idx);  taken := true; end if;
            end loop;
          when K_PRE =>
            b_open(sel_bank) <= '0';  c_act(sel_bank) <= tRP - 1;  n_pre <= n_pre + 1;
          when K_REF =>
            for b in 0 to 3 loop c_act(b) <= tRFC - 1; end loop;
            ref_pending <= '0';  refi_cnt <= 0;  n_ref <= n_ref + 1;
          when others => null;
        end case;
      end if;
    end if;
  end process;
end architecture;
