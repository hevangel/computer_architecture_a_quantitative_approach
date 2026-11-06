library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_set_assoc_cache is end entity;

architecture sim of tb_set_assoc_cache is
  constant SETS : positive := 4;  constant WAYS : positive := 2;  constant LINE_WORDS : positive := 4;
  constant ADDR_W : positive := 16;  constant DATA_W : positive := 32;  constant MEM_LAT : positive := 3;

  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal req_valid, req_we : std_logic := '0';
  signal req_addr  : std_logic_vector(ADDR_W-1 downto 0) := (others => '0');
  signal req_wdata : std_logic_vector(DATA_W-1 downto 0) := (others => '0');
  signal resp_valid : std_logic;
  signal resp_rdata : std_logic_vector(DATA_W-1 downto 0);
  signal mem_valid, mem_we : std_logic;
  signal mem_done : std_logic := '0';
  signal mem_addr  : std_logic_vector(ADDR_W-1 downto 0);
  signal mem_wdata, mem_rdata : std_logic_vector(LINE_WORDS*DATA_W-1 downto 0);
  signal hits, misses, wbs : unsigned(31 downto 0);

  type mem_t is array (0 to 2**(ADDR_W-2)-1) of std_logic_vector(DATA_W-1 downto 0);
  function init_val(w : natural) return std_logic_vector is
  begin
    return std_logic_vector(unsigned'(x"A5A50000") + to_unsigned(w, 32));
  end function;
  function init_mem return mem_t is
    variable m : mem_t;
  begin
    for i in m'range loop m(i) := init_val(i); end loop;
    return m;
  end function;
  signal mem : mem_t := init_mem;
begin
  clk <= not clk after 5 ns;

  dut : entity work.set_assoc_cache
    generic map (SETS, WAYS, LINE_WORDS, ADDR_W, DATA_W)
    port map (clk, rst_n, req_valid, req_we, req_addr, req_wdata, resp_valid, resp_rdata,
              mem_valid, mem_we, mem_addr, mem_wdata, mem_done, mem_rdata, hits, misses, wbs);

  -- main memory: fixed latency, whole-line transfers
  memory : process (clk)
    variable cnt  : natural := 0;
    variable base : natural;
  begin
    if rising_edge(clk) then
      mem_done <= '0';
      if mem_valid = '1' and mem_done = '0' then
        if cnt = MEM_LAT-1 then
          cnt := 0;  mem_done <= '1';
          base := to_integer(unsigned(mem_addr(ADDR_W-1 downto 2)));
          for k in 0 to LINE_WORDS-1 loop
            if mem_we = '1' then mem(base + k) <= mem_wdata((k+1)*DATA_W-1 downto k*DATA_W);
            else mem_rdata((k+1)*DATA_W-1 downto k*DATA_W) <= mem(base + k);
            end if;
          end loop;
        else
          cnt := cnt + 1;
        end if;
      else
        cnt := 0;
      end if;
    end if;
  end process;

  stim : process
    variable errors : natural := 0;

    procedure access_mem(we : std_logic; word : natural; wdata, expect : std_logic_vector; check : boolean) is
      variable timeout : natural := 0;
      variable done    : boolean := false;
    begin
      wait until falling_edge(clk);
      req_valid <= '1';  req_we <= we;
      req_addr  <= std_logic_vector(to_unsigned(word * 4, ADDR_W));
      req_wdata <= wdata;
      while not done loop
        wait until rising_edge(clk);
        if resp_valid = '1' then
          if check and resp_rdata /= expect then
            errors := errors + 1;
            report "FAIL read word " & integer'image(word) severity error;
          end if;
          done := true;
        else
          timeout := timeout + 1;
          if timeout > 100 then
            errors := errors + 1;  report "FAIL timeout on word " & integer'image(word) severity error;
            done := true;
          end if;
        end if;
      end loop;
      wait until falling_edge(clk);
      req_valid <= '0';  req_we <= '0';
    end procedure;

    procedure rd(word : natural; expect : std_logic_vector) is
    begin access_mem('0', word, x"00000000", expect, true); end procedure;
    procedure wr(word : natural; v : std_logic_vector) is
    begin access_mem('1', word, v, x"00000000", false); end procedure;

    procedure expect_stats(h, m, w : natural; at : string) is
    begin
      if hits /= h or misses /= m or wbs /= w then
        errors := errors + 1;
        report "FAIL stats after " & at & ": hits=" & integer'image(to_integer(hits)) &
               " misses=" & integer'image(to_integer(misses)) & " wb=" & integer'image(to_integer(wbs)) severity error;
      end if;
    end procedure;
  begin
    for i in 1 to 3 loop wait until rising_edge(clk); end loop;
    rst_n <= '1';
    -- 4 sets x 2 ways x 4 words.  Word w -> set (w/4) mod 4, tag w/16.  Words 0,16,32 collide in set 0.
    rd(0, init_val(0));   expect_stats(0, 1, 0, "R0 cold miss");
    rd(1, init_val(1));   rd(3, init_val(3));
    expect_stats(2, 1, 0, "R1,R3 hits");
    rd(4, init_val(4));   expect_stats(2, 2, 0, "R4 miss (next set)");
    wr(0, x"DEADBEEF");   rd(0, x"DEADBEEF");
    expect_stats(4, 2, 0, "W0,R0 hits");
    rd(16, init_val(16)); rd(32, init_val(32));
    expect_stats(4, 4, 1, "R16,R32: dirty eviction");
    if mem(0) /= x"DEADBEEF" then errors := errors + 1; report "FAIL write-back did not reach memory" severity error; end if;
    rd(0, x"DEADBEEF");
    expect_stats(4, 5, 1, "R0 refill (evicts clean 16)");
    rd(16, init_val(16));
    expect_stats(4, 6, 1, "R16");
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
