-- Pipelined vector machine with CHAINING (Chapter 4 / Appendix G).
-- Three pipelined functional units -- MEM (LV/SV, one memory pipe), ADD and MUL -- each take ONE element per cycle.  Vector instructions are issued
-- IN ORDER, one per cycle, to the unit they need; a unit is then busy for vl cycles and a following instruction may start as soon as the last element has
-- entered it.  A result element appears in its vector register LAT cycles after the element entered the unit.
--   CHAIN = true : a consumer element may enter its unit the cycle after the producer element was written (the units are CHAINED, elements are forwarded
--                  through the register file as they appear);   CHAIN = false : a consumer waits until the whole source vector has been written.
-- Hazards: RAW is handled per element through a count of valid elements per register (avail); WAW/WAR are checked at issue (the destination must have no
-- pending writer and no unfinished reader).  The destination of an instruction must differ from its sources.  vl is fixed while the machine runs a program.
--   op 0 LV  vd,[base+i]     op 1 SV  vs1,[base+i]     op 2 ADDV vd,vs1,vs2    op 3 SUBV vd,vs1,vs2
--   op 4 MULV vd,vs1,vs2     op 5 MULVS vd,vs1,scalar  op 6 ADDVS vd,vs1,scalar
-- Observability: st_valid(u)/st_tag_u pulse when the first element of an instruction enters unit u (u: 0 MEM, 1 ADD, 2 MUL); idle is high when nothing is in flight.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vector_chain is
  generic (CHAIN : boolean := true; LD_LAT : positive := 6; ADD_LAT : positive := 4; MUL_LAT : positive := 7);
  port (
    clk, rst_n  : in  std_logic;
    -- setup ports, use only while idle
    ld_we       : in  std_logic;
    ld_reg      : in  natural range 0 to 7;
    ld_idx      : in  natural range 0 to 15;
    ld_data     : in  std_logic_vector(31 downto 0);
    rd_reg      : in  natural range 0 to 7;
    rd_idx      : in  natural range 0 to 15;
    rd_data     : out std_logic_vector(31 downto 0);
    mem_we      : in  std_logic;
    mem_addr    : in  natural range 0 to 255;
    mem_wdata   : in  std_logic_vector(31 downto 0);
    mem_raddr   : in  natural range 0 to 255;
    mem_rdata   : out std_logic_vector(31 downto 0);
    vl          : in  natural range 0 to 16;
    -- instruction issue
    ins_valid   : in  std_logic;
    ins_op      : in  natural range 0 to 7;
    ins_vd, ins_vs1, ins_vs2 : in natural range 0 to 7;
    ins_scalar  : in  integer;
    ins_base    : in  natural range 0 to 255;
    ins_tag     : in  natural range 0 to 255;
    ins_ready   : out std_logic;
    st_valid    : out std_logic_vector(2 downto 0);
    st_tag0, st_tag1, st_tag2 : out natural;
    idle        : out std_logic
  );
end entity;

architecture rtl of vector_chain is
  constant MVL : natural := 16;  constant VREGS : natural := 8;  constant DEP : natural := 8;
  subtype word is unsigned(31 downto 0);
  type word_vrf  is array (0 to VREGS*MVL-1) of word;
  type word_mem  is array (0 to 255) of word;
  type bool3     is array (0 to 2) of boolean;
  type nat3      is array (0 to 2) of natural;
  type word3     is array (0 to 2) of word;
  type nat_v     is array (0 to VREGS-1) of natural;
  type bool_v    is array (0 to VREGS-1) of boolean;
  type bool_dl   is array (0 to 3*DEP-1) of boolean;
  type nat_dl    is array (0 to 3*DEP-1) of natural;
  type word_dl   is array (0 to 3*DEP-1) of word;

  function unit_of(op : natural) return natural is
  begin
    if op = 0 or op = 1 then return 0; elsif op = 2 or op = 3 or op = 6 then return 1; else return 2; end if;
  end function;
  function uses_s1(op : natural) return boolean is begin return op /= 0; end function;
  function uses_s2(op : natural) return boolean is begin return op = 2 or op = 3 or op = 4; end function;
  function has_dst(op : natural) return boolean is begin return op /= 1; end function;
  function exit_stage(u : natural) return natural is
  begin
    if u = 0 then return LD_LAT - 2; elsif u = 1 then return ADD_LAT - 2; else return MUL_LAT - 2; end if;
  end function;

  signal vrf : word_vrf := (others => (others => '0'));
  signal mem : word_mem := (others => (others => '0'));
  -- unit state
  signal u_act : bool3 := (others => false);
  signal u_op, u_vd, u_vs1, u_vs2, u_base, u_tag, u_idx : nat3 := (others => 0);
  type int3 is array (0 to 2) of integer;
  signal u_scal : int3 := (others => 0);
  -- register status
  signal avail : nat_v := (others => 16);
  signal readers : nat_v := (others => 0);
  signal pw : bool_v := (others => false);
  -- result delay lines, index u*DEP + stage
  signal dl_v : bool_dl := (others => false);
  signal dl_dst, dl_idx : nat_dl := (others => 0);
  signal dl_dat : word_dl := (others => (others => '0'));
  -- combinational
  signal enter, lastel : bool3 := (others => false);
  signal res : word3 := (others => (others => '0'));
  signal opa : word3 := (others => (others => '0'));
  signal ready_i : std_logic := '0';
begin
  rd_data   <= std_logic_vector(vrf(rd_reg*MVL + rd_idx));
  mem_rdata <= std_logic_vector(mem(mem_raddr));
  ins_ready <= ready_i;

  comb : process (all)
    variable en, s1ok, s2ok, last : boolean;
    variable a, b, y : word;
    variable ufree : bool3;
    variable iu : natural;
    variable busy : boolean;
  begin
    for u in 0 to 2 loop
      s1ok := (not uses_s1(u_op(u))) or (avail(u_vs1(u)) > u_idx(u));
      s2ok := (not uses_s2(u_op(u))) or (avail(u_vs2(u)) > u_idx(u));
      en   := u_act(u) and s1ok and s2ok;
      last := en and (u_idx(u) + 1 = vl);
      a := (others => '0');  b := (others => '0');  y := (others => '0');
      if u_act(u) then
        a := vrf(u_vs1(u)*MVL + u_idx(u));
        b := vrf(u_vs2(u)*MVL + u_idx(u));
        case u_op(u) is
          when 0      => y := mem((u_base(u) + u_idx(u)) mod 256);
          when 2      => y := a + b;
          when 3      => y := a - b;
          when 4      => y := resize(a * b, 32);
          when 5      => y := resize(a * unsigned(to_signed(u_scal(u), 32)), 32);
          when 6      => y := a + unsigned(to_signed(u_scal(u), 32));
          when others => y := (others => '0');
        end case;
      end if;
      enter(u) <= en;  lastel(u) <= last;  res(u) <= y;  opa(u) <= a;
      ufree(u) := (not u_act(u)) or last;
      if en and u_idx(u) = 0 then st_valid(u) <= '1'; else st_valid(u) <= '0'; end if;
    end loop;
    st_tag0 <= u_tag(0);  st_tag1 <= u_tag(1);  st_tag2 <= u_tag(2);
    iu := unit_of(ins_op);
    if ufree(iu) and ((not has_dst(ins_op)) or ((not pw(ins_vd)) and readers(ins_vd) = 0)) then ready_i <= '1'; else ready_i <= '0'; end if;
    busy := u_act(0) or u_act(1) or u_act(2);
    for r in 0 to VREGS-1 loop if pw(r) then busy := true; end if; end loop;
    if busy then idle <= '0'; else idle <= '1'; end if;
  end process;

  seq : process (clk, rst_n)
    variable n_readers : nat_v;
    variable iu, ex : natural;
  begin
    if rst_n = '0' then
      u_act <= (others => false);  u_idx <= (others => 0);
      avail <= (others => 16);  pw <= (others => false);  readers <= (others => 0);
      dl_v <= (others => false);
      vrf <= (others => (others => '0'));  mem <= (others => (others => '0'));
    elsif rising_edge(clk) then
      if ld_we = '1' then vrf(ld_reg*MVL + ld_idx) <= unsigned(ld_data);  avail(ld_reg) <= 16; end if;
      if mem_we = '1' then mem(mem_addr) <= unsigned(mem_wdata); end if;

      -- result delay lines shift; new elements enter stage 0
      for u in 0 to 2 loop
        for k in 1 to DEP-1 loop
          dl_v(u*DEP + k) <= dl_v(u*DEP + k - 1);  dl_dst(u*DEP + k) <= dl_dst(u*DEP + k - 1);
          dl_idx(u*DEP + k) <= dl_idx(u*DEP + k - 1);  dl_dat(u*DEP + k) <= dl_dat(u*DEP + k - 1);
        end loop;
        dl_v(u*DEP) <= enter(u) and has_dst(u_op(u));  dl_dst(u*DEP) <= u_vd(u);  dl_idx(u*DEP) <= u_idx(u);  dl_dat(u*DEP) <= res(u);
      end loop;
      -- write-back at the exit stage of each unit
      for u in 0 to 2 loop
        ex := u*DEP + exit_stage(u);
        if dl_v(ex) then
          vrf(dl_dst(ex)*MVL + dl_idx(ex)) <= dl_dat(ex);
          if CHAIN then avail(dl_dst(ex)) <= dl_idx(ex) + 1; end if;
          if dl_idx(ex) + 1 = vl then
            pw(dl_dst(ex)) <= false;
            avail(dl_dst(ex)) <= vl;
          end if;
        end if;
      end loop;
      -- units: advance, store, finish
      n_readers := readers;
      for u in 0 to 2 loop
        if enter(u) then
          u_idx(u) <= u_idx(u) + 1;
          if u_op(u) = 1 then mem((u_base(u) + u_idx(u)) mod 256) <= opa(u); end if;
          if lastel(u) then
            u_act(u) <= false;
            if uses_s1(u_op(u)) then n_readers(u_vs1(u)) := n_readers(u_vs1(u)) - 1; end if;
            if uses_s2(u_op(u)) then n_readers(u_vs2(u)) := n_readers(u_vs2(u)) - 1; end if;
          end if;
        end if;
      end loop;
      -- issue
      if ins_valid = '1' and ready_i = '1' then
        iu := unit_of(ins_op);
        u_act(iu) <= true;  u_op(iu) <= ins_op;  u_vd(iu) <= ins_vd;  u_vs1(iu) <= ins_vs1;  u_vs2(iu) <= ins_vs2;
        u_scal(iu) <= ins_scalar;  u_base(iu) <= ins_base;  u_tag(iu) <= ins_tag;  u_idx(iu) <= 0;
        if has_dst(ins_op) then pw(ins_vd) <= true;  avail(ins_vd) <= 0; end if;
        if uses_s1(ins_op) then n_readers(ins_vs1) := n_readers(ins_vs1) + 1; end if;
        if uses_s2(ins_op) then n_readers(ins_vs2) := n_readers(ins_vs2) + 1; end if;
      end if;
      readers <= n_readers;
    end if;
  end process;
end architecture;
