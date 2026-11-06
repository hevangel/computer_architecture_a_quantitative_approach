-- Page table (in testbench memory): vpn 0..7 valid, ppn = 0x100 + 3*vpn; vpn 5 and 6 are read-only; vpn >= 8 invalid.
-- Every response is checked against the page table alone (paddr / fault flags); the hit / miss / fault totals
-- are checked against an independent Python LRU model: directed part (5, 10, 4), whole run (130, 185, 93).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_tlb_walker is end entity;

architecture sim of tb_tlb_walker is
  constant PT_LAT : positive := 2;
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal req_valid, req_write : std_logic := '0';
  signal req_vaddr : std_logic_vector(31 downto 0) := (others => '0');
  signal resp_valid, resp_page_fault, resp_prot_fault, pt_valid : std_logic;
  signal pt_done : std_logic := '0';
  signal resp_paddr, pt_addr : std_logic_vector(31 downto 0);
  signal pt_rdata : std_logic_vector(31 downto 0) := (others => '0');
  signal hits, misses, faults : unsigned(31 downto 0);

  function pte_of(v : natural) return std_logic_vector is
    variable w : unsigned(31 downto 0) := (others => '0');
  begin
    if v < 8 then
      w := shift_left(to_unsigned(16#100# + 3 * v, 32), 12);
      w(0) := '1';
      if v /= 5 and v /= 6 then w(1) := '1'; end if;
    end if;
    return std_logic_vector(w);
  end function;
begin
  clk <= not clk after 5 ns;
  dut : entity work.tlb_walker generic map (ENTRIES => 4, PT_BASE => 0)
    port map (clk, rst_n, req_valid, req_write, req_vaddr, resp_valid, resp_paddr, resp_page_fault, resp_prot_fault,
              pt_valid, pt_addr, pt_done, pt_rdata, hits, misses, faults);

  -- page-table walker memory model
  walker_mem : process (clk)
    variable cnt : natural := 0;
  begin
    if rising_edge(clk) then
      pt_done <= '0';
      if pt_valid = '1' and pt_done = '0' then
        if cnt = PT_LAT - 1 then
          cnt := 0;  pt_done <= '1';
          pt_rdata <= pte_of(to_integer(unsigned(pt_addr(7 downto 2))));
        else cnt := cnt + 1;
        end if;
      else cnt := 0;
      end if;
    end if;
  end process;

  stim : process
    variable errors : natural := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(2002, 32);

    procedure access_page(vpn : natural; wr : boolean; off : natural) is
      variable exp_pa : unsigned(31 downto 0);
      variable exp_pf, exp_prot, done : boolean := false;
      variable timeout : natural := 0;
    begin
      exp_pf   := vpn >= 8;
      exp_prot := (not exp_pf) and wr and (vpn = 5 or vpn = 6);
      exp_pa   := shift_left(to_unsigned(16#100# + 3 * vpn, 32), 12) or to_unsigned(off, 32);
      wait until falling_edge(clk);
      req_valid <= '1';
      if wr then req_write <= '1'; else req_write <= '0'; end if;
      req_vaddr <= std_logic_vector(shift_left(to_unsigned(vpn, 32), 12) or to_unsigned(off, 32));
      while not done loop
        wait until rising_edge(clk);
        if resp_valid = '1' then
          if (resp_page_fault = '1') /= exp_pf or (resp_prot_fault = '1') /= exp_prot then
            errors := errors + 1;  report "FAIL vpn " & integer'image(vpn) & ": fault flags" severity error;
          elsif (not exp_pf) and unsigned(resp_paddr) /= exp_pa then
            errors := errors + 1;  report "FAIL vpn " & integer'image(vpn) & ": physical address" severity error;
          end if;
          done := true;
        else
          timeout := timeout + 1;
          if timeout > 50 then errors := errors + 1; report "FAIL timeout vpn " & integer'image(vpn) severity error; done := true; end if;
        end if;
      end loop;
      wait until falling_edge(clk);
      req_valid <= '0';  req_write <= '0';
    end procedure;

    procedure expect_stats(h, m, f : natural; at : string) is
    begin
      if hits /= h or misses /= m or faults /= f then
        errors := errors + 1;
        report "FAIL stats after " & at & ": hits=" & integer'image(to_integer(hits)) & " misses=" & integer'image(to_integer(misses)) &
               " faults=" & integer'image(to_integer(faults)) severity error;
      end if;
    end procedure;
  begin
    for i in 1 to 3 loop wait until rising_edge(clk); end loop;
    rst_n <= '1';
    -- directed: 4-entry fully associative TLB, LRU
    access_page(0, false, 16#010#);  access_page(0, false, 16#7F0#);        -- miss (walk), hit
    access_page(1, false, 0);  access_page(2, false, 0);  access_page(3, false, 0);   -- fill the other three entries
    access_page(0, false, 4);                                                -- hit: vpn 0 becomes MRU, vpn 1 is now LRU
    access_page(4, false, 0);                                                -- miss: evicts vpn 1
    access_page(1, false, 0);                                                -- miss again (it was evicted); evicts vpn 2
    access_page(0, false, 8);                                                -- hit: vpn 0 still resident
    access_page(5, true, 0);                                                 -- read-only page written: walk, install, protection fault
    access_page(5, false, 0);                                                -- read of the same page: hit
    access_page(5, true, 0);                                                 -- write again: hit, protection fault
    access_page(9, false, 0);  access_page(9, true, 0);                      -- invalid pages: page fault each time (nothing installed)
    access_page(2, false, 0);
    expect_stats(5, 10, 4, "directed part");
    -- pseudo-random mix of 12 pages (4 invalid), reads and writes
    for i in 0 to 299 loop
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
      access_page(to_integer(seed(19 downto 16)) mod 12, seed(24) = '1', to_integer(seed(11 downto 0)));
    end loop;
    expect_stats(130, 185, 93, "whole run");
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
