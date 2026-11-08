-- A direct-mapped cache with a hardware STRIDE PREFETCHER (reference prediction table, Chen & Baer) -- Chapter 2, "reducing miss penalty or miss rate via parallelism".
--
-- Every demand access carries the program counter of the load/store.  A small table indexed by PC remembers, per instruction, the last address,
-- the last stride and a confidence counter:
--     new stride == remembered stride (and /= 0)  ->  confidence + 1 (saturates at 2)          else  stride := new stride, confidence := 0
-- When confidence >= THRESH (two consecutive equal strides), the cache prefetches the line containing  address + stride.
--   * Demand accesses have priority: a prefetch starts only when the cache is idle, and a demand request that arrives during a prefetch waits for it.
--   * A prefetched line is installed in the cache with a "prefetched" bit.  stat_pf_useful counts the first demand hit on such a line;
--     stat_pf_issued counts prefetches sent to memory (a target line already in the cache is dropped, not counted).
--     accuracy = useful / issued;   a prefetch evicting a live line is cache POLLUTION.
--   * PREFETCH = false gives the plain cache for comparison.  Words are addressed by word number; mem_addr is a LINE number.
-- Timing: hit 1 cycle; miss MEM_LAT + 3 cycles with the testbench memory (as in victim_cache).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity stride_prefetcher is
  generic (SETS : positive := 8; LINE_WORDS : positive := 4; RPT : positive := 4; THRESH : natural := 1;
           PREFETCH : boolean := true; ADDR_W : positive := 16; DATA_W : positive := 32);
  port (
    clk, rst_n     : in  std_logic;
    req_valid      : in  std_logic;
    req_pc         : in  std_logic_vector(7 downto 0);
    req_addr       : in  std_logic_vector(ADDR_W-1 downto 0);
    resp_valid     : out std_logic;
    resp_rdata     : out std_logic_vector(DATA_W-1 downto 0);
    mem_valid      : out std_logic;
    mem_addr       : out std_logic_vector(ADDR_W-1 downto 0);          -- line number
    mem_done       : in  std_logic;
    mem_rdata      : in  std_logic_vector(LINE_WORDS*DATA_W-1 downto 0);
    stat_hits      : out unsigned(31 downto 0);                        -- demand accesses served without a miss (includes hits on prefetched lines)
    stat_misses    : out unsigned(31 downto 0);
    stat_pf_issued : out unsigned(31 downto 0);
    stat_pf_useful : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of stride_prefetcher is
  function clog2(n : positive) return natural is
    variable r : natural := 0;
    variable v : natural := 1;
  begin
    while v < n loop v := v * 2; r := r + 1; end loop;
    return r;
  end function;
  constant OFF_W : natural := clog2(LINE_WORDS);
  constant IDX_W : natural := clog2(SETS);
  constant RIDX  : natural := clog2(RPT);
  constant LN_W  : natural := ADDR_W - OFF_W;
  constant SW    : positive := ADDR_W + 1;                            -- signed width for strides / targets

  type state_t is (S_IDLE, S_DFILL, S_PFILL);
  signal state : state_t := S_IDLE;
  subtype ln_t is std_logic_vector(LN_W-1 downto 0);
  subtype word is std_logic_vector(DATA_W-1 downto 0);
  type ln_arr is array (natural range <>) of ln_t;
  type word_arr is array (natural range <>) of word;
  type addr_arr is array (0 to RPT-1) of unsigned(ADDR_W-1 downto 0);
  type stride_arr is array (0 to RPT-1) of signed(SW-1 downto 0);
  type conf_arr is array (0 to RPT-1) of natural range 0 to 2;

  signal c_line  : ln_arr(0 to SETS-1) := (others => (others => '0'));
  signal c_valid, c_pf : std_logic_vector(0 to SETS-1) := (others => '0');
  signal c_data  : word_arr(0 to SETS*LINE_WORDS-1) := (others => (others => '0'));
  signal r_valid : std_logic_vector(0 to RPT-1) := (others => '0');
  signal r_last  : addr_arr := (others => (others => '0'));
  signal r_stride : stride_arr := (others => (others => '0'));
  signal r_conf  : conf_arr := (others => 0);
  signal pf_pending : boolean := false;
  signal pf_line, pf_cur : ln_t := (others => '0');
  signal missed  : boolean := false;
  signal hits, misses, issued, useful : unsigned(31 downto 0) := (others => '0');

  signal ln : ln_t;
  signal idx, pf_idx : natural range 0 to SETS-1;
  signal woff : natural range 0 to LINE_WORDS-1;
  signal hit, pf_resident : boolean;
  -- training view of the table entry touched by this access
  signal k : natural range 0 to RPT-1;
  signal nstride, target : signed(SW-1 downto 0);
  signal nconf : natural range 0 to 2;
  signal want_pf : boolean;
begin
  stat_hits <= hits;  stat_misses <= misses;  stat_pf_issued <= issued;  stat_pf_useful <= useful;
  ln     <= req_addr(ADDR_W-1 downto OFF_W);
  idx    <= to_integer(unsigned(req_addr(OFF_W + IDX_W - 1 downto OFF_W)));
  woff   <= to_integer(unsigned(req_addr(OFF_W-1 downto 0)));
  pf_idx <= to_integer(unsigned(pf_line(IDX_W-1 downto 0)));
  hit    <= c_valid(idx) = '1' and c_line(idx) = ln;
  pf_resident <= c_valid(pf_idx) = '1' and c_line(pf_idx) = pf_line;

  resp_valid <= '1' when state = S_IDLE and req_valid = '1' and hit else '0';
  resp_rdata <= c_data(idx*LINE_WORDS + woff);
  mem_valid  <= '0' when state = S_IDLE else '1';
  mem_addr   <= std_logic_vector(resize(unsigned(pf_cur), ADDR_W)) when state = S_PFILL else std_logic_vector(resize(unsigned(ln), ADDR_W));

  train : process (all)
    variable kk : natural range 0 to RPT-1;
    variable ns, nst, tg : signed(SW-1 downto 0);
    variable nc : natural range 0 to 2;
  begin
    if RIDX = 0 then kk := 0; else kk := to_integer(unsigned(req_pc(RIDX-1 downto 0))); end if;
    k <= kk;
    ns := signed('0' & req_addr) - signed('0' & std_logic_vector(r_last(kk)));
    if r_valid(kk) = '1' and ns = r_stride(kk) and ns /= 0 then
      nst := r_stride(kk);
      if r_conf(kk) = 2 then nc := 2; else nc := r_conf(kk) + 1; end if;
    else
      if r_valid(kk) = '1' then nst := ns; else nst := (others => '0'); end if;
      nc := 0;
    end if;
    tg := signed('0' & req_addr) + nst;
    nstride <= nst;  nconf <= nc;  target <= tg;
    want_pf <= PREFETCH and r_valid(kk) = '1' and nc >= THRESH and tg(SW-1) = '0';
  end process;

  seq : process (clk, rst_n)
    variable pi : natural range 0 to SETS-1;
  begin
    if rst_n = '0' then
      state <= S_IDLE;  missed <= false;  pf_pending <= false;  pf_line <= (others => '0');  pf_cur <= (others => '0');
      hits <= (others => '0');  misses <= (others => '0');  issued <= (others => '0');  useful <= (others => '0');
      c_valid <= (others => '0');  c_pf <= (others => '0');  c_line <= (others => (others => '0'));  c_data <= (others => (others => '0'));
      r_valid <= (others => '0');  r_last <= (others => (others => '0'));  r_stride <= (others => (others => '0'));  r_conf <= (others => 0);
    elsif rising_edge(clk) then
      case state is
        when S_IDLE =>
          if req_valid = '1' then                                          -- demand has priority
            if hit then
              if not missed then hits <= hits + 1; end if;
              if c_pf(idx) = '1' then useful <= useful + 1; c_pf(idx) <= '0'; end if;
              missed <= false;
              r_valid(k) <= '1';  r_last(k) <= unsigned(req_addr);  r_stride(k) <= nstride;  r_conf(k) <= nconf;   -- train once per request
              if want_pf then pf_pending <= true; pf_line <= std_logic_vector(target(ADDR_W-1 downto OFF_W)); end if;
            else
              misses <= misses + 1;  missed <= true;  state <= S_DFILL;
            end if;
          elsif pf_pending then
            pf_pending <= false;
            if not pf_resident then pf_cur <= pf_line; issued <= issued + 1; state <= S_PFILL; end if;
          end if;
        when S_DFILL =>
          if mem_done = '1' then
            for w in 0 to LINE_WORDS-1 loop c_data(idx*LINE_WORDS + w) <= mem_rdata((w+1)*DATA_W-1 downto w*DATA_W); end loop;
            c_line(idx) <= ln;  c_valid(idx) <= '1';  c_pf(idx) <= '0';
            state <= S_IDLE;
          end if;
        when S_PFILL =>
          if mem_done = '1' then
            pi := to_integer(unsigned(pf_cur(IDX_W-1 downto 0)));
            for w in 0 to LINE_WORDS-1 loop c_data(pi*LINE_WORDS + w) <= mem_rdata((w+1)*DATA_W-1 downto w*DATA_W); end loop;
            c_line(pi) <= pf_cur;  c_valid(pi) <= '1';  c_pf(pi) <= '1';
            state <= S_IDLE;
          end if;
      end case;
    end if;
  end process;
end architecture;
