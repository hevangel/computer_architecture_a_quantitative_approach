-- Self-checking testbench for vector_chain (same tests and expected numbers as the SystemVerilog testbench).
-- Latencies: LD 6, ADD 4, MUL 7 (ST 1).  vl elements per vector, one element per cycle per unit.
--
-- (1) DAXPY  LV V1,[X]; MULVS V2,V1,5; LV V3,[Y]; ADDV V4,V2,V3; SV V4,[Y]  with the cycle numbers derived BY HAND (first issue = cycle 0,
--     d = issue cycle, s = cycle the first element enters its unit, "idle" = first cycle with nothing in flight):
--       vl = 16 chained   : d 0 1 16 17 32   s 1 7 17 23 33   idle 49        (LV V3 must wait for the single memory pipe: 3 convoys of 16 cycles)
--       vl = 16 unchained : d 0 1 16 17 32   s 1 22 17 44 63  idle 79        (each consumer waits until the whole source vector has been written)
--       vl =  8 chained   : d 0 1 8 9 16     s 1 7 9 15 19    idle 27
--       vl =  8 unchained : d 0 1 8 9 16     s 1 14 9 28 39   idle 47
--       vl =  1           : d 0 1 2 3 4      s 1 7 3 14 18    idle 19        (chaining makes no difference for one element)
-- (2) random programs: the start times are compared with a closed-form schedule (max() of the issue, unit, RAW, WAW and WAR constraints), and the final
--     register and memory contents with a sequential interpreter.
-- One harness entity per configuration (one process owns all state); the top compares the cycle counts the harnesses report.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vc_harness is
  generic (CHAIN : boolean := true);
  port (fin : out std_logic; errs : out natural; tot_daxpy16 : out natural; tot_random : out natural);
end entity;

architecture sim of vc_harness is
  signal clk : std_logic := '0';
  signal rst_n : std_logic := '0';
  signal ld_we, mem_we, ins_valid : std_logic := '0';
  signal ld_reg, rd_reg, ins_op, ins_vd, ins_vs1, ins_vs2 : natural range 0 to 7 := 0;
  signal ld_idx, rd_idx : natural range 0 to 15 := 0;
  signal ld_data, mem_wdata : std_logic_vector(31 downto 0) := (others => '0');
  signal rd_data, mem_rdata : std_logic_vector(31 downto 0);
  signal mem_addr, mem_raddr, ins_base, ins_tag : natural range 0 to 255 := 0;
  signal vl : natural range 0 to 16 := 1;
  signal ins_scalar : integer := 0;
  signal ins_ready, idle : std_logic;
  signal st_valid : std_logic_vector(2 downto 0);
  signal st_tag0, st_tag1, st_tag2 : natural;
begin
  clk <= not clk after 5 ns;

  dut : entity work.vector_chain
    generic map (CHAIN => CHAIN)
    port map (clk => clk, rst_n => rst_n, ld_we => ld_we, ld_reg => ld_reg, ld_idx => ld_idx, ld_data => ld_data, rd_reg => rd_reg, rd_idx => rd_idx,
              rd_data => rd_data, mem_we => mem_we, mem_addr => mem_addr, mem_wdata => mem_wdata, mem_raddr => mem_raddr, mem_rdata => mem_rdata,
              vl => vl, ins_valid => ins_valid, ins_op => ins_op, ins_vd => ins_vd, ins_vs1 => ins_vs1, ins_vs2 => ins_vs2, ins_scalar => ins_scalar,
              ins_base => ins_base, ins_tag => ins_tag, ins_ready => ins_ready, st_valid => st_valid, st_tag0 => st_tag0, st_tag1 => st_tag1,
              st_tag2 => st_tag2, idle => idle);

  main : process
    constant MAXI : natural := 16;
    constant LD_L : natural := 6;  constant ADD_L : natural := 4;  constant MUL_L : natural := 7;
    type int_arr  is array (natural range <>) of integer;
    type word_arr is array (natural range <>) of unsigned(31 downto 0);
    variable p_op, p_vd, p_vs1, p_vs2, p_sc, p_base : int_arr(0 to MAXI-1) := (others => 0);
    variable p_n, p_vl : integer := 0;
    variable d_log, s_log, e_d, e_s, h_d, h_s : int_arr(0 to MAXI-1) := (others => 0);
    variable h_idle, e_idle, idle_cyc, acc, cyc : integer := 0;
    variable collecting : boolean := false;
    variable sreg : word_arr(0 to 127);
    variable smem : word_arr(0 to 255);
    variable dseed : unsigned(31 downto 0) := to_unsigned(99, 32);
    variable seed  : unsigned(31 downto 0) := to_unsigned(2013, 32);
    variable nerr, tot_r, tot_d16 : integer := 0;

    function unit_of(op : integer) return integer is
    begin
      if op = 0 or op = 1 then return 0; elsif op = 2 or op = 3 or op = 6 then return 1; else return 2; end if;
    end function;
    function lat_of(op : integer) return integer is
    begin
      if op = 0 then return LD_L; elsif op = 1 then return 1; elsif unit_of(op) = 1 then return ADD_L; else return MUL_L; end if;
    end function;
    function has_dst(op : integer) return boolean is begin return op /= 1; end function;
    function imax(a, b : integer) return integer is begin if a > b then return a; else return b; end if; end function;

    -- one clock cycle: observe the rising edge (the machine's state before the edge), then return at the falling edge
    procedure neg is
    begin
      wait until rising_edge(clk);
      if collecting then
        if idle = '1' and acc = p_n and idle_cyc < 0 then idle_cyc := cyc; end if;
        if ins_valid = '1' and ins_ready = '1' then d_log(ins_tag) := cyc; acc := acc + 1; end if;
        if st_valid(0) = '1' then s_log(st_tag0) := cyc; end if;
        if st_valid(1) = '1' then s_log(st_tag1) := cyc; end if;
        if st_valid(2) = '1' then s_log(st_tag2) := cyc; end if;
      end if;
      cyc := cyc + 1;
      wait until falling_edge(clk);
    end procedure;

    impure function reads(j, r : integer) return boolean is
    begin
      return (p_op(j) /= 0 and p_vs1(j) = r) or ((p_op(j) = 2 or p_op(j) = 3 or p_op(j) = 4) and p_vs2(j) = r);
    end function;

    -- closed-form schedule
    procedure model is
      variable d, s, last, r : integer;
      variable ok : boolean;
    begin
      e_idle := 0;
      for k in 0 to p_n - 1 loop
        if k = 0 then d := 0; else d := e_d(k-1) + 1; end if;
        for j in 0 to k - 1 loop
          if unit_of(p_op(j)) = unit_of(p_op(k)) then d := imax(d, e_s(j) + p_vl - 1); end if;                       -- the unit is free
        end loop;
        if has_dst(p_op(k)) then
          for j in 0 to k - 1 loop
            if has_dst(p_op(j)) and p_vd(j) = p_vd(k) then d := imax(d, e_s(j) + p_vl - 1 + lat_of(p_op(j))); end if;   -- WAW: earlier writer finished
            if reads(j, p_vd(k)) then d := imax(d, e_s(j) + p_vl); end if;                                              -- WAR: earlier readers finished
          end loop;
        end if;
        s := d + 1;
        for w in 0 to 1 loop                                                                                           -- RAW on each source register
          if w = 0 then ok := (p_op(k) /= 0); r := p_vs1(k);
          else ok := (p_op(k) = 2 or p_op(k) = 3 or p_op(k) = 4); r := p_vs2(k); end if;
          if ok then
            last := -1;
            for j in 0 to k - 1 loop if has_dst(p_op(j)) and p_vd(j) = r then last := j; end if; end loop;
            if last >= 0 then
              if CHAIN then s := imax(s, e_s(last) + lat_of(p_op(last)));
              else s := imax(s, e_s(last) + p_vl - 1 + lat_of(p_op(last))); end if;
            end if;
          end if;
        end loop;
        e_d(k) := d;  e_s(k) := s;
        if has_dst(p_op(k)) then e_idle := imax(e_idle, s + p_vl - 1 + lat_of(p_op(k)));
        else e_idle := imax(e_idle, s + p_vl); end if;
      end loop;
    end procedure;

    -- sequential interpreter on the shadow copies (32-bit wrap-around arithmetic)
    procedure interpret is
      variable a, b, y : unsigned(31 downto 0);
    begin
      for k in 0 to p_n - 1 loop
        for i in 0 to p_vl - 1 loop
          a := sreg(p_vs1(k)*16 + i);  b := sreg(p_vs2(k)*16 + i);
          case p_op(k) is
            when 0 => sreg(p_vd(k)*16 + i) := smem((p_base(k) + i) mod 256);
            when 1 => smem((p_base(k) + i) mod 256) := a;
            when 2 => sreg(p_vd(k)*16 + i) := a + b;
            when 3 => sreg(p_vd(k)*16 + i) := a - b;
            when 4 => y := resize(a * b, 32);  sreg(p_vd(k)*16 + i) := y;
            when 5 => b := unsigned(to_signed(p_sc(k), 32));  y := resize(a * b, 32);  sreg(p_vd(k)*16 + i) := y;
            when others => b := unsigned(to_signed(p_sc(k), 32));  sreg(p_vd(k)*16 + i) := a + b;
          end case;
        end loop;
      end loop;
    end procedure;

    procedure setup is           -- random register and memory contents, loaded through the setup ports
    begin
      for r in 0 to 7 loop
        for i in 0 to 15 loop
          dseed := resize(dseed * to_unsigned(1664525, 32), 32) + to_unsigned(1013904223, 32);  sreg(r*16 + i) := dseed;
          neg;  ld_we <= '1';  ld_reg <= r;  ld_idx <= i;  ld_data <= std_logic_vector(dseed);
        end loop;
      end loop;
      for a in 0 to 255 loop
        dseed := resize(dseed * to_unsigned(1664525, 32), 32) + to_unsigned(1013904223, 32);  smem(a) := dseed;
        neg;  mem_we <= '1';  mem_addr <= a;  mem_wdata <= std_logic_vector(dseed);
      end loop;
      neg;  ld_we <= '0';  mem_we <= '0';
    end procedure;

    procedure exec_prog(what : string) is
      variable tmo : integer;
    begin
      acc := 0;  idle_cyc := -1;  collecting := true;
      neg;  vl <= p_vl;
      for k in 0 to p_n - 1 loop
        neg;
        ins_valid <= '1';  ins_op <= p_op(k);  ins_vd <= p_vd(k);  ins_vs1 <= p_vs1(k);  ins_vs2 <= p_vs2(k);  ins_scalar <= p_sc(k);  ins_base <= p_base(k);  ins_tag <= k;
        wait for 1 ns;
        tmo := 0;
        while ins_ready /= '1' and tmo < 3000 loop neg; wait for 1 ns; tmo := tmo + 1; end loop;
        if tmo >= 3000 then nerr := nerr + 1; report "FAIL [" & what & "] instruction " & integer'image(k) & " was never accepted" severity note; end if;
      end loop;
      neg;  ins_valid <= '0';
      tmo := 0;
      while idle_cyc < 0 and tmo < 3000 loop neg; tmo := tmo + 1; end loop;
      collecting := false;
      if idle_cyc < 0 then nerr := nerr + 1; report "FAIL [" & what & "] machine never became idle" severity note; end if;
      neg;
    end procedure;

    procedure check(what : string; use_hand : boolean) is
      variable t0, bad, want : integer;
    begin
      t0 := d_log(0);  bad := 0;
      for k in 0 to p_n - 1 loop
        if use_hand then want := h_d(k); else want := e_d(k); end if;
        if d_log(k) - t0 /= want then bad := bad + 1; report "FAIL [" & what & "] instr " & integer'image(k) & " issue cycle " & integer'image(d_log(k) - t0) & " expected " & integer'image(want) severity note; end if;
        if use_hand then want := h_s(k); else want := e_s(k); end if;
        if s_log(k) - t0 /= want then bad := bad + 1; report "FAIL [" & what & "] instr " & integer'image(k) & " start cycle " & integer'image(s_log(k) - t0) & " expected " & integer'image(want) severity note; end if;
      end loop;
      if use_hand then want := h_idle; else want := e_idle; end if;
      if idle_cyc - t0 /= want then bad := bad + 1; report "FAIL [" & what & "] idle at cycle " & integer'image(idle_cyc - t0) & " expected " & integer'image(want) severity note; end if;
      for r in 0 to 7 loop
        for i in 0 to 15 loop
          rd_reg <= r;  rd_idx <= i;  wait for 1 ns;
          if unsigned(rd_data) /= sreg(r*16 + i) then bad := bad + 1; if bad < 6 then report "FAIL [" & what & "] V" & integer'image(r) & "[" & integer'image(i) & "] wrong" severity note; end if; end if;
        end loop;
      end loop;
      for a in 0 to 255 loop
        mem_raddr <= a;  wait for 1 ns;
        if unsigned(mem_rdata) /= smem(a) then bad := bad + 1; if bad < 6 then report "FAIL [" & what & "] mem[" & integer'image(a) & "] wrong" severity note; end if; end if;
      end loop;
      if bad > 0 then nerr := nerr + 1; end if;
    end procedure;

    procedure set_instr(k, op, vd, s1, s2, sc, base : integer) is
    begin
      p_op(k) := op;  p_vd(k) := vd;  p_vs1(k) := s1;  p_vs2(k) := s2;  p_sc(k) := sc;  p_base(k) := base;
    end procedure;

    procedure daxpy(n : integer) is
    begin
      p_n := 5;  p_vl := n;
      set_instr(0, 0, 1, 0, 0, 0, 0);       -- LV    V1,[0]       X
      set_instr(1, 5, 2, 1, 0, 5, 0);       -- MULVS V2,V1,5
      set_instr(2, 0, 3, 0, 0, 0, 16);      -- LV    V3,[16]      Y
      set_instr(3, 2, 4, 2, 3, 0, 0);       -- ADDV  V4,V2,V3
      set_instr(4, 1, 0, 4, 0, 0, 16);      -- SV    V4,[16]
      if n = 16 then
        h_d := (0, 1, 16, 17, 32, others => 0);
        if CHAIN then h_s := (1, 7, 17, 23, 33, others => 0);  h_idle := 49;
        else          h_s := (1, 22, 17, 44, 63, others => 0); h_idle := 79; end if;
      elsif n = 8 then
        h_d := (0, 1, 8, 9, 16, others => 0);
        if CHAIN then h_s := (1, 7, 9, 15, 19, others => 0);   h_idle := 27;
        else          h_s := (1, 14, 9, 28, 39, others => 0);  h_idle := 47; end if;
      else
        h_d := (0, 1, 2, 3, 4, others => 0);
        h_s := (1, 7, 3, 14, 18, others => 0);  h_idle := 19;
      end if;
      setup;  interpret;  exec_prog("DAXPY");  model;
      check("DAXPY vl=" & integer'image(n), true);
      for k in 0 to 4 loop
        if e_d(k) /= h_d(k) or e_s(k) /= h_s(k) then nerr := nerr + 1; report "FAIL: closed-form model disagrees with the hand schedule (instr " & integer'image(k) & ")" severity note; end if;
      end loop;
      if e_idle /= h_idle then nerr := nerr + 1; report "FAIL: closed-form idle " & integer'image(e_idle) & " vs hand " & integer'image(h_idle) severity note; end if;
      if n = 16 then tot_d16 := idle_cyc - d_log(0); end if;
    end procedure;

    impure function rnd(n : positive) return integer is
    begin
      seed := resize(seed * to_unsigned(1664525, 32), 32) + to_unsigned(1013904223, 32);
      return to_integer(seed(30 downto 16)) mod n;
    end function;

    procedure random_program is
      variable op, vd, s1, s2, sc, base : integer;
    begin
      p_n := 12;
      p_vl := 1 + rnd(16);
      for k in 0 to p_n - 1 loop
        op := rnd(7);  vd := rnd(6);  s1 := rnd(6);  s2 := rnd(6);  sc := rnd(2001) - 1000;  base := rnd(240);
        if s1 = vd then s1 := (vd + 1) mod 6; end if;                    -- the destination differs from the sources
        if s2 = vd then s2 := (vd + 2) mod 6; end if;
        set_instr(k, op, vd, s1, s2, sc, base);
      end loop;
    end procedure;
  begin
    fin <= '0';  errs <= 0;  tot_daxpy16 <= 0;  tot_random <= 0;
    for i in 1 to 3 loop neg; end loop;
    rst_n <= '1';
    for i in 1 to 2 loop neg; end loop;
    daxpy(16);  daxpy(8);  daxpy(1);
    for t in 0 to 39 loop
      random_program;  setup;  interpret;  exec_prog("random");  model;
      check("random program " & integer'image(t) & " (vl=" & integer'image(p_vl) & ")", false);
      tot_r := tot_r + e_idle;
    end loop;
    errs <= nerr;  tot_daxpy16 <= tot_d16;  tot_random <= tot_r;
    fin <= '1';
    wait;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use std.env.all;

entity tb_vector_chain is
end entity;

architecture sim of tb_vector_chain is
  signal dc, dn : std_logic;
  signal ec, en, dax_c, dax_n, rnd_c, rnd_n : natural;
begin
  hc : entity work.vc_harness generic map (CHAIN => true)  port map (fin => dc, errs => ec, tot_daxpy16 => dax_c, tot_random => rnd_c);
  hn : entity work.vc_harness generic map (CHAIN => false) port map (fin => dn, errs => en, tot_daxpy16 => dax_n, tot_random => rnd_n);

  process
    variable errors : integer;
  begin
    wait until dc = '1' and dn = '1';
    errors := ec + en;
    if not (dax_c < dax_n) then errors := errors + 1; report "FAIL: chaining does not speed up DAXPY" severity note; end if;
    if not (rnd_c < rnd_n) then errors := errors + 1; report "FAIL: chaining does not speed up the random programs" severity note; end if;
    report "DAXPY vl=16: chained " & integer'image(dax_c) & " cycles, unchained " & integer'image(dax_n) & " cycles;  40 random programs: " &
           integer'image(rnd_c) & " vs " & integer'image(rnd_n) & " cycles in total" severity note;
    if errors = 0 then report "TEST PASSED"; else report "TEST FAILED: " & integer'image(errors) & " errors" severity error; end if;
    finish;
  end process;
end architecture;
