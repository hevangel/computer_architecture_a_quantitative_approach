-- A direct-mapped cache with a small fully-associative VICTIM CACHE (Jouppi, 1990) -- Chapter 2, "reducing miss rate / miss penalty".
--
-- Conflict misses happen when several hot lines map to the same set of a direct-mapped cache.  A tiny buffer next to the cache catches the
-- lines that were just evicted: on an L1 miss the buffer is probed, and on a hit the two lines are SWAPPED (the victim line moves into L1, the
-- L1 line moves into the buffer) without going to memory.  Read-only model (an instruction-cache-like path), word addresses.
--
--   L1 hit            : answered in the same cycle (1 cycle)
--   L1 miss, victim hit: swap in 1 edge, then the request replays as an L1 hit               (2 cycles, no memory access)
--   miss in both      : fetch the line from memory (mem_valid until mem_done), install in L1, the evicted L1 line goes into the
--                       victim buffer (replacing its LRU entry), then replay                    (MEM_LAT + 3 cycles with the testbench memory)
-- VICT = 0 disables the buffer (plain direct-mapped cache).  mem_addr is a LINE number.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity victim_cache is
  generic (SETS : positive := 4; LINE_WORDS : positive := 4; VICT : natural := 2; ADDR_W : positive := 16; DATA_W : positive := 32);
  port (
    clk, rst_n       : in  std_logic;
    req_valid        : in  std_logic;
    req_addr         : in  std_logic_vector(ADDR_W-1 downto 0);          -- word address
    resp_valid       : out std_logic;
    resp_rdata       : out std_logic_vector(DATA_W-1 downto 0);
    mem_valid        : out std_logic;
    mem_addr         : out std_logic_vector(ADDR_W-1 downto 0);          -- line number
    mem_done         : in  std_logic;
    mem_rdata        : in  std_logic_vector(LINE_WORDS*DATA_W-1 downto 0);
    stat_l1_hits     : out unsigned(31 downto 0);
    stat_victim_hits : out unsigned(31 downto 0);
    stat_misses      : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of victim_cache is
  function clog2(n : positive) return natural is
    variable r : natural := 0;
    variable v : natural := 1;
  begin
    while v < n loop v := v * 2; r := r + 1; end loop;
    return r;
  end function;
  constant OFF_W : natural := clog2(LINE_WORDS);
  constant IDX_W : natural := clog2(SETS);
  constant LN_W  : natural := ADDR_W - OFF_W;
  constant VN    : positive := maximum(VICT, 1);

  subtype ln_t is std_logic_vector(LN_W-1 downto 0);
  subtype word is std_logic_vector(DATA_W-1 downto 0);
  type ln_arr   is array (natural range <>) of ln_t;
  type word_arr is array (natural range <>) of word;
  type age_arr  is array (0 to VN-1) of natural range 0 to VN-1;

  signal l1_line  : ln_arr(0 to SETS-1) := (others => (others => '0'));
  signal l1_valid : std_logic_vector(0 to SETS-1) := (others => '0');
  signal l1_data  : word_arr(0 to SETS*LINE_WORDS-1) := (others => (others => '0'));
  signal v_line   : ln_arr(0 to VN-1) := (others => (others => '0'));
  signal v_valid  : std_logic_vector(0 to VN-1) := (others => '0');
  signal v_data   : word_arr(0 to VN*LINE_WORDS-1) := (others => (others => '0'));
  signal v_age    : age_arr;

  type state_t is (S_IDLE, S_FILL);
  signal state  : state_t := S_IDLE;
  signal missed : boolean := false;
  signal hits, vhits, misses : unsigned(31 downto 0) := (others => '0');

  signal ln   : ln_t;
  signal idx  : natural range 0 to SETS-1;
  signal woff : natural range 0 to LINE_WORDS-1;
  signal l1_hit, v_hit : boolean;
  signal hit_j, ins_j : natural range 0 to VN-1;
begin
  stat_l1_hits <= hits;  stat_victim_hits <= vhits;  stat_misses <= misses;
  ln   <= req_addr(ADDR_W-1 downto OFF_W);
  idx  <= to_integer(unsigned(req_addr(OFF_W + IDX_W - 1 downto OFF_W)));
  woff <= to_integer(unsigned(req_addr(OFF_W-1 downto 0)));

  lookup : process (all)
    variable have_slot : boolean;
  begin
    l1_hit <= l1_valid(idx) = '1' and l1_line(idx) = ln;
    v_hit <= false;  hit_j <= 0;
    if VICT > 0 then
      for j in 0 to VN-1 loop
        if v_valid(j) = '1' and v_line(j) = ln then v_hit <= true; hit_j <= j; end if;
      end loop;
    end if;
    have_slot := false;  ins_j <= 0;                                -- slot for an evicted line: first invalid, else LRU
    for j in 0 to VN-1 loop
      if v_valid(j) = '0' and not have_slot then ins_j <= j; have_slot := true; end if;
    end loop;
    for j in 0 to VN-1 loop
      if not have_slot and v_age(j) = VN - 1 then ins_j <= j; end if;
    end loop;
  end process;

  resp_valid <= '1' when state = S_IDLE and req_valid = '1' and l1_hit else '0';
  resp_rdata <= l1_data(idx*LINE_WORDS + woff);
  mem_valid  <= '1' when state = S_FILL else '0';
  mem_addr   <= std_logic_vector(resize(unsigned(ln), ADDR_W));

  seq : process (clk, rst_n)
  begin
    if rst_n = '0' then
      state <= S_IDLE;  missed <= false;
      hits <= (others => '0');  vhits <= (others => '0');  misses <= (others => '0');
      l1_valid <= (others => '0');  l1_line <= (others => (others => '0'));  l1_data <= (others => (others => '0'));
      v_valid <= (others => '0');  v_line <= (others => (others => '0'));  v_data <= (others => (others => '0'));
      for j in 0 to VN-1 loop v_age(j) <= j; end loop;
    elsif rising_edge(clk) then
      case state is
        when S_IDLE =>
          if req_valid = '1' then
            if l1_hit then
              if not missed then hits <= hits + 1; end if;
              missed <= false;
            elsif v_hit then                                        -- swap the victim line with the L1 line
              vhits <= vhits + 1;  missed <= true;
              for k in 0 to LINE_WORDS-1 loop
                l1_data(idx*LINE_WORDS + k)   <= v_data(hit_j*LINE_WORDS + k);
                v_data(hit_j*LINE_WORDS + k)  <= l1_data(idx*LINE_WORDS + k);
              end loop;
              l1_line(idx) <= v_line(hit_j);  l1_valid(idx) <= '1';
              v_line(hit_j) <= l1_line(idx);  v_valid(hit_j) <= l1_valid(idx);
              for j in 0 to VN-1 loop
                if v_age(j) < v_age(hit_j) then v_age(j) <= v_age(j) + 1; end if;
              end loop;
              v_age(hit_j) <= 0;
            else
              misses <= misses + 1;  missed <= true;  state <= S_FILL;
            end if;
          end if;
        when S_FILL =>
          if mem_done = '1' then
            if VICT > 0 and l1_valid(idx) = '1' then                -- the evicted L1 line becomes the most recent victim
              for k in 0 to LINE_WORDS-1 loop v_data(ins_j*LINE_WORDS + k) <= l1_data(idx*LINE_WORDS + k); end loop;
              v_line(ins_j) <= l1_line(idx);  v_valid(ins_j) <= '1';
              for j in 0 to VN-1 loop
                if v_age(j) < v_age(ins_j) then v_age(j) <= v_age(j) + 1; end if;
              end loop;
              v_age(ins_j) <= 0;
            end if;
            for k in 0 to LINE_WORDS-1 loop l1_data(idx*LINE_WORDS + k) <= mem_rdata((k+1)*DATA_W-1 downto k*DATA_W); end loop;
            l1_line(idx) <= ln;  l1_valid(idx) <= '1';
            state <= S_IDLE;
          end if;
      end case;
    end if;
  end process;
end architecture;
