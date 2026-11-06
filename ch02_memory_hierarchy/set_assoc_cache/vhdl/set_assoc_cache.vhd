-- Set-associative, write-back, write-allocate cache with true-LRU replacement.
-- WAYS = 1 gives a direct-mapped cache.  SETS, WAYS, LINE_WORDS must be powers of two,
-- SETS >= 2 and LINE_WORDS >= 2.
--
-- CPU side   : valid/ready-style.  Hold req_* stable until resp_valid is seen;
--              resp_valid is combinational (high in the cycle a hit is served).
-- Memory side: whole-line transfers; mem_valid stays high until mem_done pulses;
--              mem_addr is the byte address of the line's first word.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity set_assoc_cache is
  generic (
    SETS       : positive := 4;
    WAYS       : positive := 2;
    LINE_WORDS : positive := 4;
    ADDR_W     : positive := 16;
    DATA_W     : positive := 32
  );
  port (
    clk, rst_n      : in  std_logic;
    -- CPU side
    req_valid       : in  std_logic;
    req_we          : in  std_logic;
    req_addr        : in  std_logic_vector(ADDR_W-1 downto 0);
    req_wdata       : in  std_logic_vector(DATA_W-1 downto 0);
    resp_valid      : out std_logic;
    resp_rdata      : out std_logic_vector(DATA_W-1 downto 0);
    -- Memory side
    mem_valid       : out std_logic;
    mem_we          : out std_logic;
    mem_addr        : out std_logic_vector(ADDR_W-1 downto 0);
    mem_wdata       : out std_logic_vector(LINE_WORDS*DATA_W-1 downto 0);
    mem_done        : in  std_logic;
    mem_rdata       : in  std_logic_vector(LINE_WORDS*DATA_W-1 downto 0);
    -- Statistics
    stat_hits       : out unsigned(31 downto 0);
    stat_misses     : out unsigned(31 downto 0);
    stat_writebacks : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of set_assoc_cache is
  function clog2(n : positive) return natural is
    variable r : natural := 0;
    variable v : natural := 1;
  begin
    while v < n loop v := v * 2; r := r + 1; end loop;
    return r;
  end function;

  constant BYTE_W : natural := clog2(DATA_W / 8);
  constant OFF_W  : natural := clog2(LINE_WORDS);
  constant IDX_W  : natural := clog2(SETS);
  constant TAG_W  : natural := ADDR_W - IDX_W - OFF_W - BYTE_W;

  type state_t is (S_IDLE, S_WRITEBACK, S_REFILL);
  signal state : state_t := S_IDLE;

  type data_t is array (0 to SETS*WAYS*LINE_WORDS-1) of std_logic_vector(DATA_W-1 downto 0);
  type tag_t  is array (0 to SETS*WAYS-1) of unsigned(TAG_W-1 downto 0);
  type age_t  is array (0 to SETS*WAYS-1) of natural range 0 to WAYS-1;   -- 0 = MRU
  signal data  : data_t;
  signal tags  : tag_t;
  signal age   : age_t;
  signal valid, dirty : std_logic_vector(0 to SETS*WAYS-1);

  signal idx     : natural range 0 to SETS-1 := 0;
  signal woff    : natural range 0 to LINE_WORDS-1 := 0;
  signal tag     : unsigned(TAG_W-1 downto 0);
  signal hit     : boolean := false;
  signal hit_way, victim, victim_q : natural range 0 to WAYS-1 := 0;
  signal missed  : boolean := false;
  signal hits, misses, wbs : unsigned(31 downto 0) := (others => '0');
begin
  stat_hits <= hits;  stat_misses <= misses;  stat_writebacks <= wbs;

  -- address decode, tag lookup, victim selection
  lookup : process (all)
    variable found : boolean;
    variable i     : natural;
  begin
    idx  <= to_integer(unsigned(req_addr(BYTE_W + OFF_W + IDX_W - 1 downto BYTE_W + OFF_W)));
    woff <= to_integer(unsigned(req_addr(BYTE_W + OFF_W - 1 downto BYTE_W)));
    tag  <= unsigned(req_addr(ADDR_W-1 downto ADDR_W-TAG_W));
    i := to_integer(unsigned(req_addr(BYTE_W + OFF_W + IDX_W - 1 downto BYTE_W + OFF_W)));
    hit <= false;  hit_way <= 0;
    for w in 0 to WAYS-1 loop
      if valid(i*WAYS + w) = '1' and tags(i*WAYS + w) = unsigned(req_addr(ADDR_W-1 downto ADDR_W-TAG_W)) then
        hit <= true;  hit_way <= w;
      end if;
    end loop;
    -- victim: first invalid way, else the LRU way
    found := false;  victim <= 0;
    for w in 0 to WAYS-1 loop
      if valid(i*WAYS + w) = '0' and not found then victim <= w; found := true; end if;
    end loop;
    for w in 0 to WAYS-1 loop
      if not found and age(i*WAYS + w) = WAYS-1 then victim <= w; end if;
    end loop;
  end process;

  -- CPU-side response
  resp_valid <= '1' when state = S_IDLE and req_valid = '1' and hit else '0';
  resp_rdata <= data((idx*WAYS + hit_way)*LINE_WORDS + woff);

  -- memory-side request
  mem_valid <= '0' when state = S_IDLE else '1';
  mem_we    <= '1' when state = S_WRITEBACK else '0';
  mem_addr_p : process (all)
    variable a : std_logic_vector(ADDR_W-1 downto 0);
  begin
    a := (others => '0');
    if state = S_WRITEBACK then
      a(ADDR_W-1 downto ADDR_W-TAG_W) := std_logic_vector(tags(idx*WAYS + victim_q));
    else
      a(ADDR_W-1 downto ADDR_W-TAG_W) := std_logic_vector(tag);
    end if;
    a(ADDR_W-TAG_W-1 downto OFF_W + BYTE_W) := std_logic_vector(to_unsigned(idx, IDX_W));
    mem_addr <= a;
  end process;
  wline : process (all)
  begin
    for k in 0 to LINE_WORDS-1 loop
      mem_wdata((k+1)*DATA_W-1 downto k*DATA_W) <= data((idx*WAYS + victim_q)*LINE_WORDS + k);
    end loop;
  end process;

  seq : process (clk, rst_n)
    variable e : natural;
  begin
    if rst_n = '0' then
      state <= S_IDLE;  victim_q <= 0;  missed <= false;
      hits <= (others => '0');  misses <= (others => '0');  wbs <= (others => '0');
      valid <= (others => '0');  dirty <= (others => '0');
      for i in 0 to SETS*WAYS-1 loop
        tags(i) <= (others => '0');  age(i) <= i mod WAYS;
      end loop;
    elsif rising_edge(clk) then
      case state is
        when S_IDLE =>
          if req_valid = '1' then
            if hit then
              e := idx*WAYS + hit_way;
              if req_we = '1' then
                data(e*LINE_WORDS + woff) <= req_wdata;
                dirty(e) <= '1';
              end if;
              for w in 0 to WAYS-1 loop
                if age(idx*WAYS + w) < age(e) then age(idx*WAYS + w) <= age(idx*WAYS + w) + 1; end if;
              end loop;
              age(e) <= 0;
              if not missed then hits <= hits + 1; end if;
              missed <= false;
            else
              victim_q <= victim;
              missed   <= true;
              misses   <= misses + 1;
              if valid(idx*WAYS + victim) = '1' and dirty(idx*WAYS + victim) = '1' then
                state <= S_WRITEBACK;
              else
                state <= S_REFILL;
              end if;
            end if;
          end if;
        when S_WRITEBACK =>
          if mem_done = '1' then
            wbs <= wbs + 1;
            dirty(idx*WAYS + victim_q) <= '0';
            state <= S_REFILL;
          end if;
        when S_REFILL =>
          if mem_done = '1' then
            for k in 0 to LINE_WORDS-1 loop
              data((idx*WAYS + victim_q)*LINE_WORDS + k) <= mem_rdata((k+1)*DATA_W-1 downto k*DATA_W);
            end loop;
            tags(idx*WAYS + victim_q)  <= tag;
            valid(idx*WAYS + victim_q) <= '1';
            dirty(idx*WAYS + victim_q) <= '0';
            state <= S_IDLE;
          end if;
      end case;
    end if;
  end process;
end architecture;
