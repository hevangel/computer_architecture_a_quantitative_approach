-- Fully-associative TLB with true-LRU replacement and a hardware page-table walker (Chapter 2 / Appendix B).
--
-- Virtual address (32 bit) = { VPN (20) | page offset (12) }.  A one-level page table starts at PT_BASE; the
-- PTE for page `vpn` is the word at PT_BASE + 4*vpn:
--     PTE(31 downto 12) = physical page number    PTE(1) = W (writable)    PTE(0) = V (valid)
--
-- Protocol (same as the cache): hold req_* until resp_valid.  A TLB hit answers in the same cycle.
--   miss          -> the walker reads the PTE (pt_valid stays high until pt_done pulses);
--   V = 1         -> the entry is installed and the request is replayed as a hit;
--   V = 0         -> resp_valid with resp_page_fault (nothing is installed);
--   write to W = 0 -> resp_valid with resp_prot_fault (hit or just walked).
-- Statistics: hits = requests served by the TLB without a walk, misses = walks started, faults = page + protection faults.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tlb_walker is
  generic (ENTRIES : positive := 4; PT_BASE : natural := 0);   -- ENTRIES: power of two
  port (
    clk, rst_n      : in  std_logic;
    req_valid       : in  std_logic;
    req_write       : in  std_logic;
    req_vaddr       : in  std_logic_vector(31 downto 0);
    resp_valid      : out std_logic;
    resp_paddr      : out std_logic_vector(31 downto 0);
    resp_page_fault : out std_logic;
    resp_prot_fault : out std_logic;
    -- page-table walker memory port
    pt_valid        : out std_logic;
    pt_addr         : out std_logic_vector(31 downto 0);
    pt_done         : in  std_logic;
    pt_rdata        : in  std_logic_vector(31 downto 0);
    stat_hits       : out unsigned(31 downto 0);
    stat_misses     : out unsigned(31 downto 0);
    stat_faults     : out unsigned(31 downto 0)
  );
end entity;

architecture rtl of tlb_walker is
  type state_t is (S_IDLE, S_WALK, S_FAULT);
  signal state : state_t := S_IDLE;
  subtype vpn_t is std_logic_vector(19 downto 0);
  type vpn_arr is array (0 to ENTRIES-1) of vpn_t;
  type age_arr is array (0 to ENTRIES-1) of natural range 0 to ENTRIES-1;
  signal e_vpn, e_ppn : vpn_arr := (others => (others => '0'));
  signal e_w, e_valid : std_logic_vector(0 to ENTRIES-1) := (others => '0');
  signal e_age : age_arr;

  signal vpn : vpn_t;
  signal hit : boolean;
  signal hit_e, victim, victim_q : natural range 0 to ENTRIES-1 := 0;
  signal missed : boolean := false;
  signal prot : boolean;
  signal hits, misses, faults : unsigned(31 downto 0) := (others => '0');
begin
  stat_hits <= hits;  stat_misses <= misses;  stat_faults <= faults;
  vpn <= req_vaddr(31 downto 12);

  lookup : process (all)
    variable found : boolean;
  begin
    hit <= false;  hit_e <= 0;
    for i in 0 to ENTRIES-1 loop
      if e_valid(i) = '1' and e_vpn(i) = vpn then hit <= true; hit_e <= i; end if;
    end loop;
    found := false;  victim <= 0;
    for i in 0 to ENTRIES-1 loop
      if e_valid(i) = '0' and not found then victim <= i; found := true; end if;
    end loop;
    for i in 0 to ENTRIES-1 loop
      if not found and e_age(i) = ENTRIES-1 then victim <= i; end if;
    end loop;
  end process;

  prot <= req_write = '1' and e_w(hit_e) = '0';

  outputs : process (all)
  begin
    resp_valid <= '0';  resp_page_fault <= '0';  resp_prot_fault <= '0';
    resp_paddr <= e_ppn(hit_e) & req_vaddr(11 downto 0);
    if state = S_IDLE and req_valid = '1' and hit then
      resp_valid <= '1';
      if prot then resp_prot_fault <= '1'; end if;
    end if;
    if state = S_FAULT then resp_valid <= '1'; resp_page_fault <= '1'; end if;
    if state = S_WALK then pt_valid <= '1'; else pt_valid <= '0'; end if;
    pt_addr <= std_logic_vector(to_unsigned(PT_BASE, 32) + shift_left(resize(unsigned(vpn), 32), 2));
  end process;

  seq : process (clk, rst_n)
    variable t : natural range 0 to ENTRIES-1;
  begin
    if rst_n = '0' then
      state <= S_IDLE;  victim_q <= 0;  missed <= false;
      hits <= (others => '0');  misses <= (others => '0');  faults <= (others => '0');
      e_valid <= (others => '0');  e_vpn <= (others => (others => '0'));  e_ppn <= (others => (others => '0'));
      e_w <= (others => '0');
      for i in 0 to ENTRIES-1 loop e_age(i) <= i; end loop;
    elsif rising_edge(clk) then
      case state is
        when S_IDLE =>
          if req_valid = '1' then
            if hit then
              -- LRU update: every entry younger than the touched one ages by one; the touched one becomes MRU
              for i in 0 to ENTRIES-1 loop
                if e_age(i) < e_age(hit_e) then e_age(i) <= e_age(i) + 1; end if;
              end loop;
              e_age(hit_e) <= 0;
              if not missed then hits <= hits + 1; end if;
              if prot then faults <= faults + 1; end if;
              missed <= false;
            else
              victim_q <= victim;  missed <= true;  misses <= misses + 1;  state <= S_WALK;
            end if;
          end if;
        when S_WALK =>
          if pt_done = '1' then
            if pt_rdata(0) = '1' then                      -- valid PTE: install, then the request replays as a hit
              t := victim_q;
              e_valid(t) <= '1';  e_vpn(t) <= vpn;  e_ppn(t) <= pt_rdata(31 downto 12);  e_w(t) <= pt_rdata(1);
              for i in 0 to ENTRIES-1 loop
                if e_age(i) < e_age(t) then e_age(i) <= e_age(i) + 1; end if;
              end loop;
              e_age(t) <= 0;
              state <= S_IDLE;
            else
              state <= S_FAULT;
            end if;
          end if;
        when S_FAULT =>
          faults <= faults + 1;  missed <= false;  state <= S_IDLE;
      end case;
    end if;
  end process;
end architecture;
