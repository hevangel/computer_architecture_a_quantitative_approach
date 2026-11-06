library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_mesi_snoopy is end entity;

architecture sim of tb_mesi_snoopy is
  constant P : positive := 4;
  signal clk : std_logic := '0';
  signal rst_n, op_valid, op_write : std_logic := '0';
  signal op_core : natural range 0 to P-1 := 0;
  signal op_wdata, rdata, mem_out : std_logic_vector(31 downto 0) := (others => '0');
  signal bus_txn : std_logic_vector(1 downto 0);
  signal writeback : std_logic;
  signal state_out : std_logic_vector(2*P-1 downto 0);

  constant I : std_logic_vector(1 downto 0) := "00";
  constant S : std_logic_vector(1 downto 0) := "01";
  constant E : std_logic_vector(1 downto 0) := "10";
  constant M : std_logic_vector(1 downto 0) := "11";
  constant NONE    : std_logic_vector(1 downto 0) := "00";
  constant BUSRD   : std_logic_vector(1 downto 0) := "01";
  constant BUSRDX  : std_logic_vector(1 downto 0) := "10";
  constant BUSUPGR : std_logic_vector(1 downto 0) := "11";

  function states(a, b, c, d : std_logic_vector(1 downto 0)) return std_logic_vector is
  begin return d & c & b & a; end function;
begin
  clk <= not clk after 5 ns;
  dut : entity work.mesi_snoopy generic map (P, 32)
    port map (clk, rst_n, op_valid, op_core, op_write, op_wdata, rdata, bus_txn, writeback, state_out, mem_out);

  process
    variable errors : natural := 0;
    variable golden : std_logic_vector(31 downto 0) := (others => '0');
    variable seed   : unsigned(31 downto 0) := to_unsigned(5150, 32);

    -- perform one operation; check bus transaction, write-back flag and resulting states
    procedure op(core : natural; wr : std_logic; wdata : std_logic_vector(31 downto 0);
                 exp_txn : std_logic_vector(1 downto 0); exp_wb : std_logic;
                 exp_states : std_logic_vector(2*P-1 downto 0); what : string) is
    begin
      wait until falling_edge(clk);
      op_valid <= '1';  op_core <= core;  op_write <= wr;  op_wdata <= wdata;
      wait for 1 ns;
      if bus_txn /= exp_txn or writeback /= exp_wb then
        errors := errors + 1;  report "FAIL [" & what & "] bus transaction / write-back" severity error;
      end if;
      if wr = '0' and rdata /= golden then errors := errors + 1;  report "FAIL [" & what & "] read value" severity error; end if;
      if wr = '1' then golden := wdata; end if;
      wait until falling_edge(clk);
      op_valid <= '0';
      if state_out /= exp_states then errors := errors + 1;  report "FAIL [" & what & "] states" severity error; end if;
    end procedure;

    procedure check_invariants is
      variable owners, valids : natural := 0;
      variable cs : std_logic_vector(1 downto 0);
    begin
      for j in 0 to P-1 loop
        cs := state_out(2*j + 1 downto 2*j);
        if cs = M or cs = E then owners := owners + 1; end if;
        if cs /= I then valids := valids + 1; end if;
      end loop;
      if owners > 1 or (owners = 1 and valids > 1) then errors := errors + 1;  report "FAIL invariant: single writer" severity error; end if;
      for j in 0 to P-1 loop
        cs := state_out(2*j + 1 downto 2*j);
        if (cs = S or cs = E) and mem_out /= golden then errors := errors + 1;  report "FAIL invariant: clean copy but stale memory" severity error; end if;
      end loop;
    end procedure;

    variable core : natural;
    variable wr : std_logic;
    constant ZERO : std_logic_vector(31 downto 0) := (others => '0');
  begin
    wait until falling_edge(clk);  wait until falling_edge(clk);
    rst_n <= '1';
    op(0, '0', ZERO,       BUSRD,   '0', states(E,I,I,I), "C0 read: first reader gets Exclusive");
    op(0, '1', x"99990000", NONE,   '0', states(M,I,I,I), "C0 write in Exclusive: silent E->M, no bus traffic");
    op(1, '0', ZERO,       BUSRD,   '1', states(S,S,I,I), "C1 read: C0 flushes dirty line, both Shared");
    op(1, '1', x"AAAA0001", BUSUPGR, '0', states(I,M,I,I), "C1 write to Shared: BusUpgr invalidates C0");
    op(1, '1', x"AAAA0002", NONE,    '0', states(I,M,I,I), "C1 write hit in Modified: silent");
    op(2, '0', ZERO,       BUSRD,   '1', states(I,S,S,I), "C2 read: C1 flushes dirty line, M->S");
    if mem_out /= x"AAAA0002" then errors := errors + 1;  report "FAIL memory not updated by flush" severity error; end if;
    op(3, '1', x"BBBB0003", BUSRDX,  '0', states(I,I,I,M), "C3 write miss: BusRdX invalidates sharers");
    op(3, '1', x"BBBB0004", NONE,    '0', states(I,I,I,M), "C3 write hit in Modified: silent");
    op(0, '1', x"CCCC0005", BUSRDX,  '1', states(M,I,I,I), "C0 write miss: C3 flushes then invalidates");
    op(0, '0', ZERO,       NONE,    '0', states(M,I,I,I), "C0 read hit");
    op(2, '0', ZERO,       BUSRD,   '1', states(S,I,S,I), "C2 read: C0 flushes, M->S");
    op(2, '1', x"DDDD0006", BUSUPGR, '0', states(I,I,M,I), "C2 write to Shared: BusUpgr");
    op(3, '0', ZERO,       BUSRD,   '1', states(I,I,S,S), "C3 read: C2 flushes");
    op(2, '1', x"EEEE0007", BUSUPGR, '0', states(I,I,M,I), "C2 write: Upgr");

    -- random phase: sequential consistency + invariants
    for iter in 0 to 2999 loop
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);
      core := to_integer(seed(17 downto 16));  wr := seed(24);
      wait until falling_edge(clk);
      op_valid <= '1';  op_core <= core;  op_write <= wr;  op_wdata <= std_logic_vector(seed xor x"5A5A5A5A");
      wait for 1 ns;
      if wr = '0' and rdata /= golden then errors := errors + 1;  report "FAIL random read" severity error; end if;
      if wr = '1' then golden := std_logic_vector(seed xor x"5A5A5A5A"); end if;
      wait until falling_edge(clk);
      op_valid <= '0';
      check_invariants;
    end loop;
    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
