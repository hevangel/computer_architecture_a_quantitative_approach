-- Non-blocking, write-through cache with MSHRs and a coalescing write buffer (Chapter 2: reducing miss penalty and miss rate by parallelism).
--
-- Organisation: direct mapped, 8 sets x 4 words of 32 bits; 8-bit word addresses = tag(3) | index(3) | offset(2).  Write-through, no-write-allocate.
--   * Reads that hit answer on the hit port the next cycle (hit_*).  A read miss allocates a MISS STATUS HOLDING REGISTER (MSHR) -- or joins the MSHR already
--     fetching the same line (a SECONDARY miss, up to 4 waiting reads per MSHR) -- and the CPU port keeps accepting requests:
--         NM = number of MSHRs (outstanding line fetches);   HUM = false: BLOCKING cache (nothing is accepted while any miss is outstanding)
--                                                            HUM = true, NM = 1: hit-under-miss;   HUM = true, NM > 1: miss-under-miss
--   * A line fetch goes to memory (mem_*) once memory is ready and no WRITE BUFFER entry still holds a write to that line (reads must see earlier writes).
--     When the line arrives it is installed and its waiting reads are answered, one per cycle, on the fill port (fill_*), possibly out of order with hits.
--   * Writes update the cache on a hit and are placed in the write buffer (WBD entries, oldest first; a write to an address already buffered is MERGED into the
--     entry).  With WBD = 0 a write is accepted only in a cycle in which memory takes it.  Memory reads win the memory port over buffered writes.
--   * A write to a line with a miss outstanding waits until that miss is finished (keeps the fetched line coherent with memory).
-- req_ready is combinational and depends on the request presented.  Responses carry req_id.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity nb_cache is
  generic (NM : positive := 4; HUM : boolean := true; WBD : natural := 4);
  port (
    clk, rst_n : in  std_logic;
    req_valid, req_write : in std_logic;
    req_addr   : in  natural range 0 to 255;
    req_wdata  : in  std_logic_vector(31 downto 0);
    req_id     : in  natural range 0 to 63;
    req_ready  : out std_logic;
    hit_valid  : out std_logic;  hit_id  : out natural range 0 to 63;  hit_data  : out std_logic_vector(31 downto 0);
    fill_valid : out std_logic;  fill_id : out natural range 0 to 63;  fill_data : out std_logic_vector(31 downto 0);
    -- memory port
    mem_valid, mem_write : out std_logic;
    mem_addr   : out natural range 0 to 255;
    mem_wdata  : out std_logic_vector(31 downto 0);
    mem_tag    : out natural range 0 to 3;
    mem_ready  : in  std_logic;
    mem_rvalid : in  std_logic;
    mem_rtag   : in  natural range 0 to 3;
    mem_rline  : in  std_logic_vector(127 downto 0);
    stat_hit, stat_pri, stat_sec : out natural
  );
end entity;

architecture rtl of nb_cache is
  function wba_f return natural is begin if WBD > 0 then return WBD; else return 1; end if; end function;
  constant WBA : natural := wba_f;                                                   -- array size: WBD, at least 1
  constant S_FREE : natural := 0;  constant S_NEED : natural := 1;  constant S_WAIT : natural := 2;  constant S_FILLED : natural := 3;
  subtype word is unsigned(31 downto 0);
  type bool8 is array (0 to 7) of boolean;
  type nat8  is array (0 to 7) of natural;
  type word32 is array (0 to 31) of word;
  type nat_nm is array (0 to NM-1) of natural;
  type nat_t  is array (0 to NM*4-1) of natural;
  type line_nm is array (0 to NM-1) of std_logic_vector(127 downto 0);
  type nat_wb is array (0 to WBA-1) of natural;
  type word_wb is array (0 to WBA-1) of word;

  signal cv : bool8 := (others => false);
  signal ctag : nat8 := (others => 0);
  signal cdata : word32 := (others => (others => '0'));
  signal m_st, m_line, m_nt, m_tp : nat_nm := (others => 0);
  signal m_toff, m_tid : nat_t := (others => 0);
  signal m_data : line_nm := (others => (others => '0'));
  signal wb_addr : nat_wb := (others => 0);
  signal wb_data : word_wb := (others => (others => '0'));
  signal wb_head, wb_cnt : natural := 0;
  signal sh_hit, sh_pri, sh_sec : natural := 0;
  signal hv : std_logic := '0';
  signal hid : natural range 0 to 63 := 0;
  signal hdat : std_logic_vector(31 downto 0) := (others => '0');

  -- combinational results shared with the clocked process
  signal g_acc, g_hit, g_rd_ok, g_drain, g_merge, g_wbm, g_fany : boolean := false;
  signal g_free_m, g_merge_m, g_rd_sel, g_wbm_j, g_fill_m : natural := 0;
begin
  hit_valid <= hv;  hit_id <= hid;  hit_data <= hdat;
  stat_hit <= sh_hit;  stat_pri <= sh_pri;  stat_sec <= sh_sec;

  comb : process (all)
    variable v_idx, v_tg, v_off, v_ln, v_head : natural;
    variable v_hit, v_any, v_free_ok, v_rd_ok, v_drain, v_wblk, v_merge, v_stall, v_wbm, v_fany, v_wrok, v_rdok, v_ready, v_acc, v_mem_rdy : boolean;
    variable v_free_m, v_rd_sel, v_merge_m, v_wbm_j, v_fill_m : natural;
    variable elig : boolean_vector(0 to NM-1);
    variable wbok : boolean_vector(0 to WBA-1);
  begin
    v_idx := (req_addr / 4) mod 8;  v_tg := req_addr / 32;  v_off := req_addr mod 4;  v_ln := req_addr / 4;
    v_hit := cv(v_idx) and (ctag(v_idx) = v_tg);
    v_mem_rdy := (mem_ready = '1');
    for j in 0 to WBA-1 loop wbok(j) := (WBD > 0) and (((j + WBA - wb_head) mod WBA) < wb_cnt); end loop;
    v_head := wb_head mod WBA;
    -- MSHR status
    v_any := false;  v_free_ok := false;  v_free_m := 0;
    for m in NM-1 downto 0 loop
      if m_st(m) /= S_FREE then v_any := true; else v_free_ok := true; v_free_m := m; end if;
    end loop;
    -- which MSHR may fetch its line now
    v_rd_ok := false;  v_rd_sel := 0;
    for m in NM-1 downto 0 loop
      elig(m) := (m_st(m) = S_NEED) and v_mem_rdy;
      for j in 0 to WBA-1 loop if wbok(j) and (wb_addr(j) / 4 = m_line(m)) then elig(m) := false; end if; end loop;
      if elig(m) then v_rd_ok := true; v_rd_sel := m; end if;
    end loop;
    v_drain := (WBD > 0) and (wb_cnt /= 0) and v_mem_rdy and (not v_rd_ok);
    -- fill port
    v_fany := false;  v_fill_m := 0;
    for m in NM-1 downto 0 loop if m_st(m) = S_FILLED then v_fany := true; v_fill_m := m; end if; end loop;
    if v_fany then fill_valid <= '1'; else fill_valid <= '0'; end if;
    fill_id   <= m_tid(v_fill_m * 4 + m_tp(v_fill_m));
    fill_data <= m_data(v_fill_m)(32 * m_toff(v_fill_m * 4 + m_tp(v_fill_m)) + 31 downto 32 * m_toff(v_fill_m * 4 + m_tp(v_fill_m)));
    -- request dependent
    v_merge := false;  v_merge_m := 0;  v_stall := false;  v_wblk := false;
    for m in NM-1 downto 0 loop
      if m_st(m) /= S_FREE and m_line(m) = v_ln then v_wblk := true; end if;
      if (m_st(m) = S_NEED or m_st(m) = S_WAIT) and m_line(m) = v_ln then
        if m_nt(m) < 4 then v_merge := true; v_merge_m := m; else v_stall := true; end if;
      end if;
    end loop;
    v_wbm := false;  v_wbm_j := 0;
    for j in WBA-1 downto 0 loop
      if wbok(j) and wb_addr(j) = req_addr and not (v_drain and j = v_head) then v_wbm := true; v_wbm_j := j; end if;
    end loop;
    v_rdok := v_hit or v_merge or ((not v_stall) and v_free_ok);
    if WBD > 0 then v_wrok := (not v_wblk) and (v_wbm or (wb_cnt < WBD));
    else            v_wrok := (not v_wblk) and (v_mem_rdy and (not v_rd_ok)); end if;
    if req_write = '1' then v_ready := (HUM or (not v_any)) and v_wrok; else v_ready := (HUM or (not v_any)) and v_rdok; end if;
    v_acc := (req_valid = '1') and v_ready;
    if v_ready then req_ready <= '1'; else req_ready <= '0'; end if;
    -- memory port
    mem_valid <= '0';  mem_write <= '0';  mem_addr <= 0;  mem_wdata <= (others => '0');  mem_tag <= 0;
    if v_rd_ok then
      mem_valid <= '1';  mem_addr <= m_line(v_rd_sel) * 4;  mem_tag <= v_rd_sel;
    elsif v_drain then
      mem_valid <= '1';  mem_write <= '1';  mem_addr <= wb_addr(v_head);  mem_wdata <= std_logic_vector(wb_data(v_head));
    elsif WBD = 0 and v_acc and req_write = '1' then
      mem_valid <= '1';  mem_write <= '1';  mem_addr <= req_addr;  mem_wdata <= req_wdata;
    end if;
    g_acc <= v_acc;  g_hit <= v_hit;  g_rd_ok <= v_rd_ok;  g_drain <= v_drain;  g_merge <= v_merge;  g_wbm <= v_wbm;  g_fany <= v_fany;
    g_free_m <= v_free_m;  g_merge_m <= v_merge_m;  g_rd_sel <= v_rd_sel;  g_wbm_j <= v_wbm_j;  g_fill_m <= v_fill_m;
  end process;

  seq : process (clk, rst_n)
    variable v_idx, v_off, v_ln, v_m, v_il, v_tail : natural;
  begin
    if rst_n = '0' then
      cv <= (others => false);  ctag <= (others => 0);  cdata <= (others => (others => '0'));
      m_st <= (others => S_FREE);  m_nt <= (others => 0);  m_tp <= (others => 0);  m_line <= (others => 0);
      wb_head <= 0;  wb_cnt <= 0;  hv <= '0';  sh_hit <= 0;  sh_pri <= 0;  sh_sec <= 0;
    elsif rising_edge(clk) then
      hv <= '0';
      v_idx := (req_addr / 4) mod 8;  v_off := req_addr mod 4;  v_ln := req_addr / 4;
      -- line arrives: install it and hand it to the MSHR
      if mem_rvalid = '1' then
        v_m := mem_rtag;  v_il := m_line(v_m) mod 8;
        cv(v_il) <= true;  ctag(v_il) <= m_line(v_m) / 8;
        for k in 0 to 3 loop cdata(v_il * 4 + k) <= unsigned(mem_rline(32 * k + 31 downto 32 * k)); end loop;
        m_data(v_m) <= mem_rline;  m_st(v_m) <= S_FILLED;  m_tp(v_m) <= 0;
      end if;
      -- fill port: answer the next waiting read of the oldest filled MSHR
      if g_fany then
        if m_tp(g_fill_m) + 1 = m_nt(g_fill_m) then m_st(g_fill_m) <= S_FREE; else m_tp(g_fill_m) <= m_tp(g_fill_m) + 1; end if;
      end if;
      -- memory takes a line fetch
      if g_rd_ok then m_st(g_rd_sel) <= S_WAIT; end if;
      -- write buffer drains its oldest entry
      if g_drain then wb_head <= (wb_head + 1) mod WBA;  wb_cnt <= wb_cnt - 1; end if;
      -- the CPU request
      if g_acc then
        if req_write = '0' then
          if g_hit then
            hv <= '1';  hid <= req_id;  hdat <= std_logic_vector(cdata(v_idx * 4 + v_off));  sh_hit <= sh_hit + 1;
          elsif g_merge then
            m_toff(g_merge_m * 4 + m_nt(g_merge_m)) <= v_off;  m_tid(g_merge_m * 4 + m_nt(g_merge_m)) <= req_id;
            m_nt(g_merge_m) <= m_nt(g_merge_m) + 1;  sh_sec <= sh_sec + 1;
          else
            m_st(g_free_m) <= S_NEED;  m_line(g_free_m) <= v_ln;  m_nt(g_free_m) <= 1;
            m_toff(g_free_m * 4) <= v_off;  m_tid(g_free_m * 4) <= req_id;  sh_pri <= sh_pri + 1;
          end if;
        else
          -- a write that hits the line being replaced this very cycle must not touch the newly installed line (memory gets the write via the buffer)
          if g_hit and not (mem_rvalid = '1' and (m_line(mem_rtag) mod 8) = v_idx) then cdata(v_idx * 4 + v_off) <= unsigned(req_wdata); end if;
          if WBD > 0 then
            if g_wbm then wb_data(g_wbm_j) <= unsigned(req_wdata);
            else
              v_tail := (wb_head + wb_cnt) mod WBA;
              wb_addr(v_tail) <= req_addr;  wb_data(v_tail) <= unsigned(req_wdata);
              if g_drain then wb_cnt <= wb_cnt; else wb_cnt <= wb_cnt + 1; end if;      -- push and drain in one cycle: occupancy unchanged
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
