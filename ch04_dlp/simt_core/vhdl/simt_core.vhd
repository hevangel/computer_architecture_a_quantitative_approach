-- A small GPU-style SIMT core (Chapter 4): NW warps of WS lanes sharing one instruction stream per warp.
--
--   * Each cycle a round-robin scheduler picks one READY warp and issues one instruction for all of its ACTIVE lanes at once.
--   * A load makes its warp ineligible: the dependent instruction can issue LD_LAT edges after the load.  Other warps run in
--     the meantime -- this is how a GPU hides memory latency (multithreading instead of caches/out-of-order).
--   * Branch divergence uses a per-warp reconvergence stack (as in NVIDIA's SSY/SYNC scheme):
--        SSY            push {mask = current active mask}                        (marks a reconvergence region)
--        BEQZ ra, T     lanes with ra == 0 want pc = T, the others fall through.  If both groups exist the warp DIVERGES:
--                       push {pc = T, mask = taken lanes} and continue with the not-taken lanes.
--        SYNC           pop: a pending path -> run it (pc = its pc, mask = its mask); an SSY token -> restore its mask, pc + 1
--   * Lanes run with the active mask; masked-off lanes do nothing.  Lane utilisation = lane_ops / (issued * WS).
--
-- Instruction word: (31:27) op | (26:23) rd | (22:19) ra | (18:15) rb | (14:0) imm (sign-extended); registers r0..r7 per lane, r0 = 0.
--   0 NOP | 1 ADD | 2 SUB | 3 MUL | 5 ANDI rd=ra&imm | 6 ADDI rd=ra+imm | 7 TID rd=global thread id | 8 LD rd=mem[ra+imm]
--   9 ST mem[ra+imm]=rb | 10 BEQZ ra,imm | 11 BRA imm | 12 SSY | 13 SYNC | 14 EXIT.      Memory is word addressed, one port per lane.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity simt_core is
  generic (NW : positive := 4; WS : positive := 8; LD_LAT : positive := 6; DEPTH : positive := 4);   -- LD_LAT >= 2
  port (
    clk, rst_n   : in  std_logic;
    imem_addr    : out std_logic_vector(7 downto 0);
    imem_rdata   : in  std_logic_vector(31 downto 0);
    dmem_addr    : out std_logic_vector(WS*16-1 downto 0);       -- one word address per lane
    dmem_wdata   : out std_logic_vector(WS*32-1 downto 0);
    dmem_we      : out std_logic_vector(WS-1 downto 0);
    dmem_rdata   : in  std_logic_vector(WS*32-1 downto 0);
    all_done     : out std_logic;
    stat_cycles  : out unsigned(31 downto 0);
    stat_issued  : out unsigned(31 downto 0);                    -- warp-instructions
    stat_lane_ops : out unsigned(31 downto 0);                   -- sum over issued instructions of the active-lane count
    stat_idle    : out unsigned(31 downto 0)                     -- cycles with no warp ready
  );
end entity;

architecture rtl of simt_core is
  constant NREG : positive := 8;
  subtype word is std_logic_vector(31 downto 0);
  subtype mask_t is std_logic_vector(WS-1 downto 0);
  type pc_arr    is array (0 to NW-1) of natural range 0 to 255;
  type mask_arr  is array (natural range <>) of mask_t;
  type word_arr  is array (natural range <>) of word;
  type nat_arr   is array (natural range <>) of natural;

  signal pc     : pc_arr := (others => 0);
  signal mask   : mask_arr(0 to NW-1) := (others => (others => '1'));
  signal done   : std_logic_vector(0 to NW-1) := (others => '0');
  signal waitc  : nat_arr(0 to NW-1) := (others => 0);
  signal sp     : nat_arr(0 to NW-1) := (others => 0);
  signal st_pc  : nat_arr(0 to NW*DEPTH-1) := (others => 0);
  signal st_mask : mask_arr(0 to NW*DEPTH-1) := (others => (others => '0'));
  signal st_kind : std_logic_vector(0 to NW*DEPTH-1) := (others => '0');       -- 0 = pending path, 1 = SSY token
  signal regs   : word_arr(0 to NW*WS*NREG-1) := (others => (others => '0'));
  signal ld_data : word_arr(0 to NW*WS-1) := (others => (others => '0'));
  signal ld_rd  : nat_arr(0 to NW-1) := (others => 0);
  signal ld_mask : mask_arr(0 to NW-1) := (others => (others => '0'));
  signal rr     : natural range 0 to NW-1 := NW - 1;
  signal cycles, issued, lane_ops, idle : unsigned(31 downto 0) := (others => '0');

  -- combinational results
  signal found : boolean;
  signal sel : natural range 0 to NW-1;
  signal op, rdn, ran, rbn : natural;
  signal imm : signed(31 downto 0);
  signal amask, taken, nottaken : mask_t;
  signal a_l, b_l : word_arr(0 to WS-1);
  signal nactive : natural range 0 to WS;
  signal all_d : std_logic;
begin
  stat_cycles <= cycles;  stat_issued <= issued;  stat_lane_ops <= lane_ops;  stat_idle <= idle;
  all_d    <= '1' when done = (done'range => '1') else '0';
  all_done <= all_d;

  -- ---- scheduler, decode, per-lane operand fetch ------------------------------------------------------
  comb : process (all)
    variable w : natural range 0 to NW-1;
    variable fnd : boolean;
    variable sl : natural range 0 to NW-1;
    variable ins : word;
    variable rd_v, ra_v, rb_v : natural;
    variable im : signed(31 downto 0);
    variable am, tk, nt : mask_t;
    variable av, bv : word;
    variable cnt : natural range 0 to WS;
  begin
    fnd := false;  sl := 0;
    for k in 1 to NW loop
      w := (rr + k) mod NW;
      if not fnd and done(w) = '0' and waitc(w) = 0 then fnd := true; sl := w; end if;
    end loop;
    found <= fnd;  sel <= sl;
    imem_addr <= std_logic_vector(to_unsigned(pc(sl), 8));
    ins := imem_rdata;
    op <= to_integer(unsigned(ins(31 downto 27)));
    rd_v := to_integer(unsigned(ins(26 downto 23)));  ra_v := to_integer(unsigned(ins(22 downto 19)));  rb_v := to_integer(unsigned(ins(18 downto 15)));
    rdn <= rd_v;  ran <= ra_v;  rbn <= rb_v;
    im := resize(signed(ins(14 downto 0)), 32);
    imm <= im;
    am := mask(sl);  amask <= am;
    tk := (others => '0');  nt := (others => '0');  cnt := 0;
    for l in 0 to WS-1 loop
      if (ra_v mod 8) = 0 then av := (others => '0'); else av := regs((sl*WS + l)*NREG + (ra_v mod 8)); end if;
      if (rb_v mod 8) = 0 then bv := (others => '0'); else bv := regs((sl*WS + l)*NREG + (rb_v mod 8)); end if;
      a_l(l) <= av;  b_l(l) <= bv;
      dmem_addr(16*l + 15 downto 16*l) <= std_logic_vector(resize(signed(av) + im, 16));
      dmem_wdata(32*l + 31 downto 32*l) <= bv;
      if fnd and all_d = '0' and ins(31 downto 27) = "01001" and am(l) = '1' then dmem_we(l) <= '1'; else dmem_we(l) <= '0'; end if;
      if am(l) = '1' then
        cnt := cnt + 1;
        if unsigned(av) = 0 then tk(l) := '1'; else nt(l) := '1'; end if;
      end if;
    end loop;
    taken <= tk;  nottaken <= nt;  nactive <= cnt;
  end process;

  -- ---- the clocked machine --------------------------------------------------------------------------------
  seq : process (clk, rst_n)
    variable base : natural;
    variable ri : natural;
    variable top : natural;
    variable newpc : natural range 0 to 255;
  begin
    if rst_n = '0' then
      rr <= NW - 1;
      cycles <= (others => '0');  issued <= (others => '0');  lane_ops <= (others => '0');  idle <= (others => '0');
      pc <= (others => 0);  mask <= (others => (others => '1'));  done <= (others => '0');  waitc <= (others => 0);  sp <= (others => 0);
      ld_rd <= (others => 0);  ld_mask <= (others => (others => '0'));
      st_pc <= (others => 0);  st_mask <= (others => (others => '0'));  st_kind <= (others => '0');
      regs <= (others => (others => '0'));  ld_data <= (others => (others => '0'));
    elsif rising_edge(clk) and all_d = '0' then
      cycles <= cycles + 1;
      -- outstanding loads: count down, write the registers when the data "arrives"
      for w in 0 to NW-1 loop
        if waitc(w) /= 0 then
          waitc(w) <= waitc(w) - 1;
          if waitc(w) = 1 then
            for l in 0 to WS-1 loop
              if ld_mask(w)(l) = '1' and (ld_rd(w) mod 8) /= 0 then regs((w*WS + l)*NREG + (ld_rd(w) mod 8)) <= ld_data(w*WS + l); end if;
            end loop;
          end if;
        end if;
      end loop;
      if not found then
        idle <= idle + 1;
      else
        rr <= sel;
        issued <= issued + 1;
        lane_ops <= lane_ops + nactive;
        pc(sel) <= pc(sel) + 1;                                       -- default; control instructions override below
        for l in 0 to WS-1 loop
          if amask(l) = '1' and (rdn mod 8) /= 0 then
            ri := (sel*WS + l)*NREG + (rdn mod 8);
            case op is
              when 1  => regs(ri) <= std_logic_vector(unsigned(a_l(l)) + unsigned(b_l(l)));
              when 2  => regs(ri) <= std_logic_vector(unsigned(a_l(l)) - unsigned(b_l(l)));
              when 3  => regs(ri) <= std_logic_vector(resize(unsigned(a_l(l)) * unsigned(b_l(l)), 32));
              when 5  => regs(ri) <= a_l(l) and std_logic_vector(imm);
              when 6  => regs(ri) <= std_logic_vector(unsigned(a_l(l)) + unsigned(imm));
              when 7  => regs(ri) <= std_logic_vector(to_unsigned(sel*WS + l, 32));
              when others => null;
            end case;
          end if;
        end loop;
        base := sel * DEPTH;
        case op is
          when 8 =>                                                   -- load: data captured now, registers written LD_LAT-1 edges later
            for l in 0 to WS-1 loop ld_data(sel*WS + l) <= dmem_rdata(32*l + 31 downto 32*l); end loop;
            ld_rd(sel) <= rdn;  ld_mask(sel) <= amask;  waitc(sel) <= LD_LAT - 1;
          when 10 =>                                                  -- BEQZ
            if taken = (taken'range => '0') then null;                -- nobody jumps: fall through
            elsif nottaken = (nottaken'range => '0') then pc(sel) <= to_integer(unsigned(std_logic_vector(imm(7 downto 0))));   -- everybody jumps
            else                                                      -- divergence: run the fall-through lanes first
              st_pc(base + sp(sel)) <= to_integer(unsigned(std_logic_vector(imm(7 downto 0))));
              st_mask(base + sp(sel)) <= taken;
              st_kind(base + sp(sel)) <= '0';
              sp(sel) <= sp(sel) + 1;
              mask(sel) <= nottaken;
            end if;
          when 11 => pc(sel) <= to_integer(unsigned(std_logic_vector(imm(7 downto 0))));      -- BRA
          when 12 =>                                                  -- SSY: remember the mask to restore at reconvergence
            st_pc(base + sp(sel)) <= 0;
            st_mask(base + sp(sel)) <= amask;
            st_kind(base + sp(sel)) <= '1';
            sp(sel) <= sp(sel) + 1;
          when 13 =>                                                  -- SYNC: pop
            top := base + sp(sel) - 1;
            sp(sel) <= sp(sel) - 1;
            mask(sel) <= st_mask(top);
            if st_kind(top) = '0' then pc(sel) <= st_pc(top); end if;
          when 14 => done(sel) <= '1';  pc(sel) <= pc(sel);           -- EXIT
          when others => null;
        end case;
      end if;
    end if;
  end process;
end architecture;
