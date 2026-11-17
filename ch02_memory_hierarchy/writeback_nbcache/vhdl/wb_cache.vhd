-- Non-blocking WRITE-BACK cache with write-allocate, MSHRs and a write-back (victim) buffer (Chapter 2 / Appendix B).
--
-- Organisation: 8 sets x 4 words of 32 bits, one or two ways; 8-bit word addresses = tag(3) | index(3) | offset(2); a valid bit and a DIRTY bit per line.
--   * Hits: reads answer on hit_* the next cycle; a store updates the line and sets its dirty bit -- NO memory traffic.
--   * Misses (reads AND stores: write-allocate) go through an MSHR (NM of them; HUM = false makes the cache blocking).  A miss to a line whose fetch has not yet
--     returned joins that MSHR as a target (up to 4 targets: loads and stores, in program order).  A request to a line whose MSHR has already returned its data
--     and is finishing stalls until the line is installed.
--   * When the line returns, its targets are processed one per cycle in order (a load answers on fill_*, a store patches the line and marks it dirty).  Then the line is
--     INSTALLED: a dirty victim is moved to the WRITE-BACK BUFFER (WBD line entries) -- off the critical path of the miss -- and written to memory when the memory port is
--     free. With FORWARD_WB enabled, the newest buffered copy supplies an MSHR; otherwise its fetch waits for write-back.
--   * If the write-back buffer is full an install with a dirty victim waits.  A request that hits the index being installed in this very cycle waits one cycle.
--   * flush = '1' (cache idle) writes every dirty line back and raises flush_done when memory has them all.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wb_cache is
  generic (NM : positive := 4; HUM : boolean := true; WBD : positive := 2; FORWARD_WB : boolean := false; WAYS : positive := 1);
  port (
    clk, rst_n : in  std_logic;
    req_valid, req_write : in std_logic;
    req_addr   : in  natural range 0 to 255;
    req_wdata  : in  std_logic_vector(31 downto 0);
    req_id     : in  natural range 0 to 63;
    req_ready  : out std_logic;
    hit_valid  : out std_logic;  hit_id  : out natural range 0 to 63;  hit_data  : out std_logic_vector(31 downto 0);
    fill_valid : out std_logic;  fill_id : out natural range 0 to 63;  fill_data : out std_logic_vector(31 downto 0);
    flush      : in  std_logic;
    flush_done : out std_logic;
    -- memory port
    mem_valid, mem_write : out std_logic;
    mem_addr   : out natural range 0 to 255;
    mem_wdata  : out std_logic_vector(127 downto 0);
    mem_tag    : out natural range 0 to 3;
    mem_ready  : in  std_logic;
    mem_rvalid : in  std_logic;
    mem_rtag   : in  natural range 0 to 3;
    mem_rline  : in  std_logic_vector(127 downto 0);
    stat_hit, stat_pri, stat_sec, stat_wb : out natural
  );
end entity;

architecture rtl of wb_cache is
  constant S_FREE : natural := 0;  constant S_NEED : natural := 1;  constant S_WAIT : natural := 2;  constant S_FILLED : natural := 3;  constant S_INSTALL : natural := 4;
  subtype word is unsigned(31 downto 0);
  subtype line_t is std_logic_vector(127 downto 0);
  type bool8 is array (0 to 8*WAYS-1) of boolean;
  type lru_t is array (0 to 7) of natural range 0 to 1;
  type nat8  is array (0 to 8*WAYS-1) of natural;
  type word32 is array (0 to 32*WAYS-1) of word;
  type nat_nm is array (0 to NM-1) of natural;
  type bool_nm is array (0 to NM-1) of boolean;
  type line_nm is array (0 to NM-1) of line_t;
  type nat_t  is array (0 to NM*4-1) of natural;
  type bool_t is array (0 to NM*4-1) of boolean;
  type word_t is array (0 to NM*4-1) of word;
  type nat_wb is array (0 to WBD-1) of natural;
  type line_wb is array (0 to WBD-1) of line_t;

  signal lru : lru_t := (others=>0);
  signal cv, cd : bool8 := (others => false);
  signal ctag : nat8 := (others => 0);
  signal cdata : word32 := (others => (others => '0'));
  signal m_st, m_line, m_nt, m_tp : nat_nm := (others => 0);
  signal m_dirty : bool_nm := (others => false);
  signal m_data : line_nm := (others => (others => '0'));
  signal t_wr : bool_t := (others => false);
  signal t_off, t_id : nat_t := (others => 0);
  signal t_data : word_t := (others => (others => '0'));
  signal wbl_line : nat_wb := (others => 0);
  signal wbl_data : line_wb := (others => (others => '0'));
  signal wb_head, wb_cnt, fidx : natural := 0;
  signal sh_hit, sh_pri, sh_sec, sh_wb : natural := 0;
  signal hv : std_logic := '0';
  signal hid : natural range 0 to 63 := 0;
  signal hdat : std_logic_vector(31 downto 0) := (others => '0');

  -- combinational results shared with the clocked process
  signal g_acc, g_hit, g_merge, g_rd_ok, g_drain, g_fany, g_inst, g_push, g_fl_adv, g_fl_push : boolean := false;
  signal g_free_m, g_merge_m, g_rd_sel, g_fill_m, g_inst_m, g_tgt, g_push_line, g_hit_entry, g_inst_entry, g_flush_entry : natural := 0;
  signal g_forward : boolean := false;
  signal g_forward_m, g_forward_slot : natural := 0;
  signal g_push_data : line_t := (others => '0');
begin
  assert WAYS=1 or WAYS=2 report "WAYS must be 1 or 2" severity failure;
  hit_valid <= hv;  hit_id <= hid;  hit_data <= hdat;
  stat_hit <= sh_hit;  stat_pri <= sh_pri;  stat_sec <= sh_sec;  stat_wb <= sh_wb;

  comb : process (all)
    variable v_idx, v_tg, v_off, v_ln, v_head, v_inst_m, v_inst_idx, v_fill_m, v_tgt, v_free_m, v_rd_sel, v_merge_m, v_push_line, v_fi : natural;
    variable v_hit, v_any, v_free_ok, v_rd_ok, v_drain, v_fany, v_inst_any, v_inst_ok, v_inst_now, v_vict, v_blocked, v_flact, v_fldirty, v_flpush, v_fladv : boolean;
    variable v_push, v_merge, v_actm, v_okreq, v_ready, v_acc, v_mem_rdy : boolean;
    variable elig : boolean_vector(0 to NM-1);
    variable v_vdata, v_pdata : line_t;
    variable v_hit_entry, v_inst_entry : natural;
    variable v_forward : boolean; variable v_forward_m, v_forward_slot, slot : natural;
  begin
    v_idx := (req_addr / 4) mod 8;  v_tg := req_addr / 32;  v_off := req_addr mod 4;  v_ln := req_addr / 4;
    v_hit := false; v_hit_entry := v_idx*WAYS;
    for w in 0 to WAYS-1 loop
      if cv(v_idx*WAYS+w) and ctag(v_idx*WAYS+w)=v_tg then
        v_hit := true; v_hit_entry := v_idx*WAYS+w;
      end if;
    end loop;
    v_mem_rdy := (mem_ready = '1');
    v_head := wb_head mod WBD;
    v_any := false;  v_free_ok := false;  v_free_m := 0;
    for m in NM-1 downto 0 loop
      if m_st(m) /= S_FREE then v_any := true; else v_free_ok := true; v_free_m := m; end if;
    end loop;
    -- fetch: state NEED, memory ready, no write-back-buffer entry for the line
    v_rd_ok := false;  v_rd_sel := 0;
    v_forward := false; v_forward_m := 0; v_forward_slot := 0;
    for m in NM-1 downto 0 loop
      elig(m) := (m_st(m) = S_NEED) and v_mem_rdy;
      for k in 0 to WBD-1 loop
        slot := (wb_head + k) mod WBD;
        if k < wb_cnt and wbl_line(slot) = m_line(m) then
          elig(m) := false;
          if FORWARD_WB and m_st(m) = S_NEED then
            v_forward := true; v_forward_m := m; v_forward_slot := slot;
          end if;
        end if;
      end loop;
      if elig(m) then v_rd_ok := true; v_rd_sel := m; end if;
    end loop;
    v_drain := (wb_cnt /= 0) and v_mem_rdy and (not v_rd_ok);
    -- filled MSHR: process its next target
    v_fany := false;  v_fill_m := 0;
    for m in NM-1 downto 0 loop if m_st(m) = S_FILLED then v_fany := true; v_fill_m := m; end if; end loop;
    v_tgt := v_fill_m * 4 + m_tp(v_fill_m);
    if v_fany and not t_wr(v_tgt) then fill_valid <= '1'; else fill_valid <= '0'; end if;
    fill_id   <= t_id(v_tgt);
    fill_data <= m_data(v_fill_m)(32 * t_off(v_tgt) + 31 downto 32 * t_off(v_tgt));
    -- install
    v_inst_any := false;  v_inst_m := 0;
    for m in NM-1 downto 0 loop if m_st(m) = S_INSTALL then v_inst_any := true; v_inst_m := m; end if; end loop;
    v_inst_idx := m_line(v_inst_m) mod 8;
    v_inst_entry := v_inst_idx*WAYS;
    if WAYS=2 then
      if not cv(v_inst_idx*WAYS) then v_inst_entry:=v_inst_idx*WAYS;
      elsif not cv(v_inst_idx*WAYS+1) then v_inst_entry:=v_inst_idx*WAYS+1;
      else v_inst_entry:=v_inst_idx*WAYS+lru(v_inst_idx); end if;
    end if;
    v_vict := cv(v_inst_entry) and cd(v_inst_entry);
    v_inst_ok := v_inst_any and ((not v_vict) or (wb_cnt < WBD));
    v_inst_now := v_inst_ok and (flush = '0');
    for k in 0 to 3 loop v_vdata(32 * k + 31 downto 32 * k) := std_logic_vector(cdata(v_inst_entry * 4 + k)); end loop;
    -- flush
    v_flact := (flush = '1') and (not v_any);
    v_fi := fidx mod (8*WAYS);
    v_fldirty := (fidx < 8*WAYS) and cv(v_fi) and cd(v_fi);
    v_flpush := v_flact and v_fldirty and (wb_cnt < WBD);
    v_fladv := v_flact and (fidx < 8*WAYS) and ((not v_fldirty) or (wb_cnt < WBD));
    if (flush = '1') and (fidx = 8*WAYS) and (wb_cnt = 0) and (not v_any) then flush_done <= '1'; else flush_done <= '0'; end if;
    for k in 0 to 3 loop v_pdata(32 * k + 31 downto 32 * k) := std_logic_vector(cdata(v_fi * 4 + k)); end loop;
    v_push := (v_inst_now and v_vict) or v_flpush;
    if v_inst_now and v_vict then v_push_line := ctag(v_inst_entry) * 8 + v_inst_idx; g_push_data <= v_vdata;
    else                          v_push_line := ctag(v_fi) * 8 + v_fi/WAYS;             g_push_data <= v_pdata; end if;
    -- request
    v_merge := false;  v_merge_m := 0;  v_actm := false;
    for m in NM-1 downto 0 loop
      if m_st(m) /= S_FREE and m_line(m) = v_ln then v_actm := true; end if;
      if (m_st(m) = S_NEED or m_st(m) = S_WAIT) and m_line(m) = v_ln and m_nt(m) < 4 then v_merge := true; v_merge_m := m; end if;
    end loop;
    v_blocked := v_inst_now and (v_inst_idx = v_idx);
    v_okreq := v_hit or v_merge or ((not v_actm) and v_free_ok);
    v_ready := (flush = '0') and (not v_blocked) and (HUM or (not v_any)) and v_okreq;
    v_acc := (req_valid = '1') and v_ready;
    if v_ready then req_ready <= '1'; else req_ready <= '0'; end if;
    -- memory port
    mem_valid <= '0';  mem_write <= '0';  mem_addr <= 0;  mem_wdata <= (others => '0');  mem_tag <= 0;
    if v_rd_ok then
      mem_valid <= '1';  mem_addr <= m_line(v_rd_sel) * 4;  mem_tag <= v_rd_sel;
    elsif v_drain then
      mem_valid <= '1';  mem_write <= '1';  mem_addr <= wbl_line(v_head) * 4;  mem_wdata <= wbl_data(v_head);
    end if;
    g_hit_entry<=v_hit_entry; g_inst_entry<=v_inst_entry; g_flush_entry<=v_fi;
    g_forward <= v_forward; g_forward_m <= v_forward_m; g_forward_slot <= v_forward_slot;
    g_acc <= v_acc;  g_hit <= v_hit;  g_merge <= v_merge;  g_rd_ok <= v_rd_ok;  g_drain <= v_drain;  g_fany <= v_fany;  g_inst <= v_inst_now;  g_push <= v_push;
    g_fl_adv <= v_fladv;  g_fl_push <= v_flpush;
    g_free_m <= v_free_m;  g_merge_m <= v_merge_m;  g_rd_sel <= v_rd_sel;  g_fill_m <= v_fill_m;  g_inst_m <= v_inst_m;  g_tgt <= v_tgt;  g_push_line <= v_push_line;
  end process;

  seq : process (clk, rst_n)
    variable v_idx, v_off, v_ln, v_m, v_il, v_tail, v_cnt : natural;
    variable dtmp : line_t;
  begin
    if rst_n = '0' then
      cv <= (others => false);  cd <= (others => false); lru <= (others=>0);  ctag <= (others => 0);  cdata <= (others => (others => '0'));
      m_st <= (others => S_FREE);  m_nt <= (others => 0);  m_tp <= (others => 0);  m_line <= (others => 0);  m_dirty <= (others => false);
      wb_head <= 0;  wb_cnt <= 0;  fidx <= 0;  hv <= '0';  sh_hit <= 0;  sh_pri <= 0;  sh_sec <= 0;  sh_wb <= 0;
    elsif rising_edge(clk) then
      hv <= '0';
      v_idx := (req_addr / 4) mod 8;  v_off := req_addr mod 4;  v_ln := req_addr / 4;
      if flush = '0' then fidx <= 0; elsif g_fl_adv then fidx <= fidx + 1; end if;
      -- line arrives
      if mem_rvalid = '1' then
        v_m := mem_rtag;
        m_data(v_m) <= mem_rline;  m_st(v_m) <= S_FILLED;  m_tp(v_m) <= 0;  m_dirty(v_m) <= false;
      end if;
      -- Forward the newest buffered copy; its pending write still drains in FIFO order.
      if g_forward then
        m_data(g_forward_m) <= wbl_data(g_forward_slot); m_st(g_forward_m) <= S_FILLED;
        m_tp(g_forward_m) <= 0; m_dirty(g_forward_m) <= false;
      end if;
      -- process the next target of the oldest filled MSHR
      if g_fany then
        if t_wr(g_tgt) then
          dtmp := m_data(g_fill_m);
          dtmp(32 * t_off(g_tgt) + 31 downto 32 * t_off(g_tgt)) := std_logic_vector(t_data(g_tgt));
          m_data(g_fill_m) <= dtmp;  m_dirty(g_fill_m) <= true;
        end if;
        if m_tp(g_fill_m) + 1 = m_nt(g_fill_m) then m_st(g_fill_m) <= S_INSTALL; else m_tp(g_fill_m) <= m_tp(g_fill_m) + 1; end if;
      end if;
      -- install a finished line
      if g_inst then
        v_il := m_line(g_inst_m) mod 8;
        cv(g_inst_entry) <= true;  ctag(g_inst_entry) <= m_line(g_inst_m) / 8;  cd(g_inst_entry) <= m_dirty(g_inst_m);
        if WAYS=2 then lru(v_il)<=1-(g_inst_entry mod WAYS); end if;
        for k in 0 to 3 loop cdata(g_inst_entry * 4 + k) <= unsigned(m_data(g_inst_m)(32 * k + 31 downto 32 * k)); end loop;
        m_st(g_inst_m) <= S_FREE;
      end if;
      if g_fl_push then cd(g_flush_entry) <= false; end if;
      -- memory takes a fetch / a write-back
      if g_rd_ok then m_st(g_rd_sel) <= S_WAIT; end if;
      if g_drain then wb_head <= (wb_head + 1) mod WBD;  sh_wb <= sh_wb + 1; end if;
      if g_push then
        v_tail := (wb_head + wb_cnt) mod WBD;
        wbl_line(v_tail) <= g_push_line;  wbl_data(v_tail) <= g_push_data;
      end if;
      v_cnt := wb_cnt;
      if g_push then v_cnt := v_cnt + 1; end if;
      if g_drain then v_cnt := v_cnt - 1; end if;
      wb_cnt <= v_cnt;
      -- the CPU request
      if g_acc then
        if g_hit then
          if WAYS=2 then lru(v_idx)<=1-(g_hit_entry mod WAYS); end if;
          if req_write = '0' then
            hv <= '1';  hid <= req_id;  hdat <= std_logic_vector(cdata(g_hit_entry * 4 + v_off));  sh_hit <= sh_hit + 1;
          else
            cdata(g_hit_entry * 4 + v_off) <= unsigned(req_wdata);  cd(g_hit_entry) <= true;  sh_hit <= sh_hit + 1;
          end if;
        elsif g_merge then
          t_wr(g_merge_m * 4 + m_nt(g_merge_m)) <= (req_write = '1');  t_off(g_merge_m * 4 + m_nt(g_merge_m)) <= v_off;
          t_id(g_merge_m * 4 + m_nt(g_merge_m)) <= req_id;  t_data(g_merge_m * 4 + m_nt(g_merge_m)) <= unsigned(req_wdata);
          m_nt(g_merge_m) <= m_nt(g_merge_m) + 1;  sh_sec <= sh_sec + 1;
        else
          m_st(g_free_m) <= S_NEED;  m_line(g_free_m) <= v_ln;  m_nt(g_free_m) <= 1;
          t_wr(g_free_m * 4) <= (req_write = '1');  t_off(g_free_m * 4) <= v_off;  t_id(g_free_m * 4) <= req_id;  t_data(g_free_m * 4) <= unsigned(req_wdata);
          sh_pri <= sh_pri + 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
