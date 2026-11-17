-- Tomasulo ROB/LSQ with speculative loads and suffix replay.
-- Based on the repository's tomasulo_lsq teaching core; older work survives
-- memory-order and resolve-time branch recovery. Addresses wrap modulo 64.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tomasulo_mem_spec_replay is
  generic (
    NREG : positive := 8;  ROBN : positive := 8;  NADD : positive := 3;  NMUL : positive := 2;  NLSQ : positive := 8;
    ADD_LAT : positive := 2;  MUL_LAT : positive := 4;  LD_LAT : positive := 3;  FWD_LAT : positive := 1;
    PREDICT_BTFN : boolean := false;  FORWARD : boolean := true; SPEC_MEM : boolean := true; RESOLVE_BRANCH : boolean := true; DW : positive := 32
  );
  port (
    clk, rst_n     : in  std_logic;
    init_we        : in  std_logic;                       -- initialise registers while stopped and empty
    init_reg       : in  natural range 0 to NREG-1;
    init_data      : in  std_logic_vector(DW-1 downto 0);
    dinit_we       : in  std_logic;                       -- initialise data memory while stopped and empty
    dinit_addr     : in  natural range 0 to 63;
    dinit_data     : in  std_logic_vector(DW-1 downto 0);
    start          : in  std_logic;                       -- begin fetching at pc = 0 (first issue at the next edge)
    imem_addr      : out std_logic_vector(7 downto 0);
    imem_rdata     : in  std_logic_vector(31 downto 0);
    halted         : out std_logic;
    stat_cycles    : out unsigned(31 downto 0);
    stat_committed : out unsigned(31 downto 0);
    stat_branches  : out unsigned(31 downto 0);
    stat_flushes   : out unsigned(31 downto 0);
    stat_squashed  : out unsigned(31 downto 0);
    stat_loads     : out unsigned(31 downto 0);
    stat_stores    : out unsigned(31 downto 0);
    stat_fwd       : out unsigned(31 downto 0);
    stat_replays   : out unsigned(31 downto 0);
    dbg_raddr      : in  natural range 0 to NREG-1;
    dbg_rdata      : out std_logic_vector(DW-1 downto 0);
    dbg_maddr      : in  natural range 0 to 63;
    dbg_mdata      : out std_logic_vector(DW-1 downto 0)
  );
end entity;

architecture rtl of tomasulo_mem_spec_replay is
  constant NRS : positive := NADD + NMUL;
  type data_t is array (natural range <>) of std_logic_vector(DW-1 downto 0);
  type int_t  is array (natural range <>) of natural;

  signal regfile    : data_t(0 to NREG-1) := (others => (others => '0'));
  signal regst_busy : std_logic_vector(0 to NREG-1) := (others => '0');
  signal regst_tag  : int_t(0 to NREG-1) := (others => 0);
  signal dmem       : data_t(0 to 63) := (others => (others => '0'));
  signal rob_done, rob_wr, rob_br, rob_halt, rob_pred, rob_mem, rob_st : std_logic_vector(0 to ROBN-1) := (others => '0');
  signal rob_tgt, rob_ft, rob_pc, rob_reg : int_t(0 to ROBN-1) := (others => 0);
  signal rob_val  : data_t(0 to ROBN-1) := (others => (others => '0'));
  signal head, tail : natural range 0 to ROBN-1 := 0;
  signal count : natural range 0 to ROBN := 0;
  signal rs_busy, rs_exec, rs_qjw, rs_qkw : std_logic_vector(0 to NRS-1) := (others => '0');
  signal rs_op, rs_qjt, rs_qkt, rs_dest : int_t(0 to NRS-1) := (others => 0);
  signal rs_vj, rs_vk : data_t(0 to NRS-1) := (others => (others => '0'));
  -- load/store queue
  signal lq_v, lq_st, lq_addr_v, lq_exec, lq_qjw, lq_qkw : std_logic_vector(0 to NLSQ-1) := (others => '0');
  signal lq_addr, lq_qjt, lq_qkt, lq_imm, lq_rob : int_t(0 to NLSQ-1) := (others => 0);
  type mask_t is array(0 to NLSQ-1) of std_logic_vector(0 to NLSQ-1);
  signal lq_unknown:mask_t:=(others=>(others=>'0'));
  signal lq_vj, lq_vk : data_t(0 to NLSQ-1) := (others => (others => '0'));
  signal lsq_head, lsq_tail : natural range 0 to NLSQ-1 := 0;
  signal lsq_cnt : natural range 0 to NLSQ := 0;
  -- units: 0 add, 1 multiply, 2 load
  signal u_busy, u_done : std_logic_vector(0 to 2) := (others => '0');
  signal u_rs, u_rem : int_t(0 to 2) := (others => 0);
  signal u_res : data_t(0 to 2) := (others => (others => '0'));
  signal u_fwd : std_logic := '0';
  signal u_fv : std_logic_vector(DW-1 downto 0) := (others => '0');
  signal pc : natural range 0 to 255 := 0;
  signal running, fetch_stop, halted_i : std_logic := '0';
  signal cycles, committed, branches, flushes, squashed, loads, stores, fwds, replays : unsigned(31 downto 0) := (others => '0');

  signal cdb_v : std_logic;
  signal cdb_t, cdb_u : natural range 0 to ROBN;
  signal cdb_val : std_logic_vector(DW-1 downto 0);
  signal free_rs : integer range -1 to NRS-1;
  signal src_val  : data_t(0 to 1);
  signal src_wait : std_logic_vector(0 to 1);
  signal src_tag  : int_t(0 to 1);
  signal issue_ok : std_logic;
  signal i_op, i_rd, i_rs, i_rt, i_tgt, i_imm : natural;
  signal do_commit, flush_now, do_issue, br_actual, pred_taken : boolean;
  signal recover_now,recover_branch:boolean:=false;
  signal recover_keep:natural range 0 to ROBN+1:=0; signal recover_pc:natural range 0 to 255:=0;

  function alu(op : natural; a, b : std_logic_vector) return std_logic_vector is
  begin
    case op is
      when 0      => return std_logic_vector(unsigned(a) + unsigned(b));
      when 1      => return std_logic_vector(unsigned(a) - unsigned(b));
      when 2      => return std_logic_vector(resize(unsigned(a) * unsigned(b), DW));
      when others => return a;                                  -- branch: the condition value
    end case;
  end function;
  function ldist(j, h : natural) return natural is begin return (j + NLSQ - h) mod NLSQ; end function;
  function rdist(j,h:natural) return natural is begin return (j+ROBN-h) mod ROBN; end function;
begin
  dbg_rdata <= regfile(dbg_raddr);
  dbg_mdata <= dmem(dbg_maddr);
  imem_addr <= std_logic_vector(to_unsigned(pc, 8));
  halted <= halted_i;
  stat_cycles <= cycles;  stat_committed <= committed;  stat_branches <= branches;  stat_flushes <= flushes;  stat_squashed <= squashed;
  stat_loads <= loads;  stat_stores <= stores;  stat_fwd <= fwds; stat_replays<=replays;

  -- ---- common data bus (priority: add unit, multiplier, load unit) -----------------------------------------
  cdb_arb : process (all)
    variable usel : natural range 0 to 2;
    variable any_v : boolean;
  begin
    cdb_v <= '0';  cdb_u <= 0;  cdb_t <= 0;  cdb_val <= (others => '0');
    usel := 0;  any_v := false;
    if u_done(0) = '1' then any_v := true; usel := 0;
    elsif u_done(1) = '1' then any_v := true; usel := 1;
    elsif u_done(2) = '1' then any_v := true; usel := 2;
    end if;
    cdb_u <= usel;
    if any_v then
      cdb_v <= '1';  cdb_val <= u_res(usel);
      if usel = 2 then cdb_t <= lq_rob(u_rs(2)); else cdb_t <= rs_dest(u_rs(usel)); end if;
    end if;
  end process;

  -- ---- fetch/decode of the instruction at pc, free station, operand lookup -----------------------------------
  i_op  <= to_integer(unsigned(imem_rdata(31 downto 28)));
  i_rd  <= to_integer(unsigned(imem_rdata(26 downto 24)));
  i_rs  <= to_integer(unsigned(imem_rdata(22 downto 20)));
  i_rt  <= to_integer(unsigned(imem_rdata(18 downto 16)));
  i_tgt <= to_integer(unsigned(imem_rdata(7 downto 0)));
  i_imm <= to_integer(unsigned(imem_rdata(5 downto 0)));

  issue_lookup : process (all)
    variable fr : integer range -1 to NRS-1;
    variable r  : natural range 0 to NREG-1;
    variable tg : natural range 0 to ROBN-1;
    variable alu_i, br_i, halt_i, mul_i, ld_i, st_i, ok : boolean;
  begin
    alu_i := i_op <= 2;  br_i := i_op = 3;  halt_i := i_op = 4;  mul_i := i_op = 2;  ld_i := i_op = 5;  st_i := i_op = 6;
    fr := -1;
    for i in 0 to NRS-1 loop
      if rs_busy(i) = '0' and fr < 0 and ((i >= NADD) = mul_i) then fr := i; end if;
    end loop;
    free_rs <= fr;
    ok := running = '1' and halted_i = '0' and fetch_stop = '0' and count < ROBN and
          (halt_i or ((alu_i or br_i) and fr >= 0) or ((ld_i or st_i) and lsq_cnt < NLSQ));
    if ok then issue_ok <= '1'; else issue_ok <= '0'; end if;

    for s in 0 to 1 loop
      if s = 0 then r := i_rs; else r := i_rt; end if;
      src_val(s) <= regfile(r);  src_wait(s) <= '0';  src_tag(s) <= 0;
      if regst_busy(r) = '1' then
        tg := regst_tag(r);
        src_tag(s) <= tg;
        if cdb_v = '1' and cdb_t = tg then src_val(s) <= cdb_val;
        elsif rob_done(tg) = '1' then src_val(s) <= rob_val(tg);
        else src_wait(s) <= '1';
        end if;
      end if;
      if s = 1 and (br_i or ld_i) then src_val(1) <= (others => '0'); src_wait(1) <= '0'; end if;   -- one source only
    end loop;
  end process;

  -- ---- commit / misprediction detection ------------------------------------------------------------------------
  do_commit  <= count /= 0 and rob_done(head) = '1';
  br_actual  <= unsigned(rob_val(head)) /= 0;
  flush_now  <= (not RESOLVE_BRANCH) and do_commit and rob_br(head) = '1' and (br_actual /= (rob_pred(head) = '1'));
  do_issue   <= issue_ok = '1' and not flush_now and not recover_now;
  pred_taken <= PREDICT_BTFN and i_op = 3 and i_tgt < pc;

  choose_recovery:process(all)
    variable yes,branch,wrong,candidate:boolean; variable keep,tag,pc_v,age:natural;
  begin
    yes:=false; branch:=false; keep:=ROBN+1; tag:=0; pc_v:=0;
    wrong:=RESOLVE_BRANCH and cdb_v='1' and rob_br(cdb_t)='1' and ((unsigned(cdb_val)/=0)/=(rob_pred(cdb_t)='1'));
    if wrong then
      yes:=true; branch:=true; tag:=cdb_t; keep:=rdist(cdb_t,head)+1;
      if unsigned(cdb_val)/=0 then pc_v:=rob_tgt(cdb_t); else pc_v:=rob_ft(cdb_t); end if;
    end if;
    if SPEC_MEM then
      for j in 0 to NLSQ-1 loop
        if lq_v(j)='1' and lq_st(j)='0' and lq_exec(j)='1' and lq_addr_v(j)='1' then
          candidate:=false;
          for k in 0 to NLSQ-1 loop
            if lq_unknown(j)(k)='1' and lq_v(k)='1' and lq_st(k)='1' and lq_addr_v(k)='1' and lq_addr(k)=lq_addr(j) then candidate:=true; end if;
          end loop;
          age:=rdist(lq_rob(j),head);
          if candidate and age<keep then yes:=true; branch:=false; keep:=age; tag:=lq_rob(j); pc_v:=rob_pc(tag); end if;
        end if;
      end loop;
    end if;
    recover_now<=yes; recover_branch<=branch; recover_keep<=keep; recover_pc<=pc_v;
  end process;

  seq : process (clk, rst_n)
    variable pick, ms, pa : integer;
    variable lo, hi : natural;
    variable cu : natural range 0 to 2;
    variable nxt, nl : integer;
    variable alu_i, br_i, halt_i, ld_i, st_i, mem_i : boolean;
    variable pbit : std_logic;
    variable age_i, age_p : natural;
    variable ok, blocked, fwd : boolean;
    variable fvv : std_logic_vector(DW-1 downto 0);
    variable ad : natural;
    variable keep_lsq,tag_index,new_tag:natural; variable found:boolean;
  begin
    if rst_n = '0' then
      head <= 0;  tail <= 0;  count <= 0;  pc <= 0;  running <= '0';  fetch_stop <= '0';  halted_i <= '0';
      lsq_head <= 0;  lsq_tail <= 0;  lsq_cnt <= 0;
      cycles <= (others => '0');  committed <= (others => '0');  branches <= (others => '0');
      flushes <= (others => '0');  squashed <= (others => '0');  loads <= (others => '0');  stores <= (others => '0');  fwds <= (others => '0'); replays <= (others=>'0');
      regfile <= (others => (others => '0'));  regst_busy <= (others => '0');  regst_tag <= (others => 0);
      dmem <= (others => (others => '0'));
      rob_done <= (others => '0');  rob_wr <= (others => '0');  rob_br <= (others => '0');  rob_halt <= (others => '0');  rob_mem <= (others => '0');  rob_st <= (others => '0');
      rob_pred <= (others => '0');  rob_tgt <= (others => 0);  rob_ft <= (others => 0); rob_pc <= (others=>0);  rob_reg <= (others => 0);
      rob_val <= (others => (others => '0'));
      rs_busy <= (others => '0');  rs_exec <= (others => '0');  rs_qjw <= (others => '0');  rs_qkw <= (others => '0');
      rs_op <= (others => 0);  rs_qjt <= (others => 0);  rs_qkt <= (others => 0);  rs_dest <= (others => 0);
      rs_vj <= (others => (others => '0'));  rs_vk <= (others => (others => '0'));
      lq_v <= (others => '0');  lq_st <= (others => '0');  lq_addr_v <= (others => '0');  lq_exec <= (others => '0');  lq_qjw <= (others => '0');  lq_qkw <= (others => '0');
      lq_addr <= (others => 0);  lq_qjt <= (others => 0);  lq_qkt <= (others => 0);  lq_imm <= (others => 0);  lq_rob <= (others => 0);
      lq_unknown <= (others=>(others=>'0'));
      lq_vj <= (others => (others => '0'));  lq_vk <= (others => (others => '0'));
      u_busy <= (others => '0');  u_done <= (others => '0');  u_rs <= (others => 0);  u_rem <= (others => 0);
      u_res <= (others => (others => '0'));  u_fwd <= '0';  u_fv <= (others => '0');
    elsif rising_edge(clk) then
      cu := cdb_u;
      alu_i := i_op <= 2;  br_i := i_op = 3;  halt_i := i_op = 4;  ld_i := i_op = 5;  st_i := i_op = 6;  mem_i := ld_i or st_i;
      if init_we = '1' and running = '0' and count = 0 then regfile(init_reg) <= init_data; end if;
      if dinit_we = '1' and running = '0' and count = 0 then dmem(dinit_addr) <= dinit_data; end if;
      if start = '1' and running = '0' then running <= '1'; end if;
      if running = '1' and halted_i = '0' then cycles <= cycles + 1; end if;

      -- 1. CDB broadcast
      if cdb_v = '1' then
        rob_val(cdb_t)  <= cdb_val;
        rob_done(cdb_t) <= '1';
        for i in 0 to NRS-1 loop
          if rs_busy(i) = '1' and rs_qjw(i) = '1' and rs_qjt(i) = cdb_t then rs_vj(i) <= cdb_val; rs_qjw(i) <= '0'; end if;
          if rs_busy(i) = '1' and rs_qkw(i) = '1' and rs_qkt(i) = cdb_t then rs_vk(i) <= cdb_val; rs_qkw(i) <= '0'; end if;
        end loop;
        for j in 0 to NLSQ-1 loop
          if lq_v(j) = '1' and lq_qjw(j) = '1' and lq_qjt(j) = cdb_t then lq_vj(j) <= cdb_val; lq_qjw(j) <= '0'; end if;
          if lq_v(j) = '1' and lq_qkw(j) = '1' and lq_qkt(j) = cdb_t then lq_vk(j) <= cdb_val; lq_qkw(j) <= '0'; end if;
        end loop;
      end if;

      -- 2. functional units (add, multiply, load)
      for u in 0 to 2 loop
        if u = 0 then lo := 0; hi := NADD - 1; else lo := NADD; hi := NRS - 1; end if;
        if u_busy(u) = '0' then
         if not recover_now then
          pick := -1;
          if u < 2 then
            for i in lo to hi loop
              if rs_busy(i) = '1' and rs_exec(i) = '0' and rs_qjw(i) = '0' and rs_qkw(i) = '0' then
                if pick < 0 then pick := i;
                else
                  age_i := (rs_dest(i) + ROBN - head) mod ROBN;
                  age_p := (rs_dest(pick) + ROBN - head) mod ROBN;
                  if age_i < age_p then pick := i; end if;
                end if;
              end if;
            end loop;
            if pick >= 0 then
              u_busy(u) <= '1';  u_done(u) <= '0';  u_rs(u) <= pick;
              if u = 0 then u_rem(u) <= ADD_LAT; else u_rem(u) <= MUL_LAT; end if;
              rs_exec(pick) <= '1';
            end if;
          else
            -- the oldest load whose address is known and which no older store can still change
            fwd := false;  fvv := (others => '0');
            for j in 0 to NLSQ-1 loop
              if lq_v(j) = '1' and lq_st(j) = '0' and lq_exec(j) = '0' and lq_addr_v(j) = '1' then
                ok := true;  blocked := false;  ms := -1;
                for k in 0 to NLSQ-1 loop
                  if lq_v(k) = '1' and lq_st(k) = '1' and ldist(k, lsq_head) < ldist(j, lsq_head) then
                    if lq_addr_v(k) = '0' then blocked := true;                                      -- an older store with an unknown address
                    elsif lq_addr(k) = lq_addr(j) then
                      if ms < 0 then ms := k; elsif ldist(k, lsq_head) > ldist(ms, lsq_head) then ms := k; end if;   -- the youngest older store to the same address
                    end if;
                  end if;
                end loop;
                if blocked and not SPEC_MEM then ok := false; end if;
                if ok and ms >= 0 then
                  if (not FORWARD) or lq_qkw(ms) = '1' then ok := false; end if;                    -- must wait for the store (data or commit)
                end if;
                if ok then
                  if pick < 0 then
                    pick := j;  fwd := ms >= 0;
                    if ms >= 0 then fvv := lq_vk(ms); else fvv := (others => '0'); end if;
                  elsif ldist(j, lsq_head) < ldist(pick, lsq_head) then
                    pick := j;  fwd := ms >= 0;
                    if ms >= 0 then fvv := lq_vk(ms); else fvv := (others => '0'); end if;
                  end if;
                end if;
              end if;
            end loop;
            if pick >= 0 then
              u_busy(2) <= '1';  u_done(2) <= '0';  u_rs(2) <= pick;
              if fwd then u_rem(2) <= FWD_LAT; u_fwd <= '1'; fwds <= fwds + 1; else u_rem(2) <= LD_LAT; u_fwd <= '0'; end if;
              u_fv <= fvv;
              lq_exec(pick) <= '1';
              for k in 0 to NLSQ-1 loop
                if SPEC_MEM and lq_v(k)='1' and lq_st(k)='1' and lq_addr_v(k)='0' and ldist(k,lsq_head)<ldist(pick,lsq_head) then lq_unknown(pick)(k)<='1'; else lq_unknown(pick)(k)<='0'; end if;
              end loop;
            end if;
          end if;
         end if;
        elsif u_done(u) = '0' then
          if u_rem(u) = 1 then
            u_done(u) <= '1';  u_rem(u) <= 0;
            if u < 2 then u_res(u) <= alu(rs_op(u_rs(u)), rs_vj(u_rs(u)), rs_vk(u_rs(u)));
            elsif u_fwd = '1' then u_res(u) <= u_fv;
            else u_res(u) <= dmem(lq_addr(u_rs(2)));
            end if;
          else
            u_rem(u) <= u_rem(u) - 1;
          end if;
        elsif cdb_v = '1' and cu = u then
          u_busy(u) <= '0';  u_done(u) <= '0';
          if u < 2 then rs_busy(u_rs(u)) <= '0';  rs_exec(u_rs(u)) <= '0'; end if;
        end if;
      end loop;

      for j in 0 to NLSQ-1 loop
        if lq_v(j)='1' and lq_st(j)='0' and lq_exec(j)='1' then
          for k in 0 to NLSQ-1 loop if lq_unknown(j)(k)='1' and (lq_v(k)='0' or lq_addr_v(k)='1') then lq_unknown(j)(k)<='0'; end if; end loop;
        end if;
      end loop;
      -- 3. address unit: the oldest queue entry with an available base register gets its address
      pa := -1;
      for j in 0 to NLSQ-1 loop
        if lq_v(j) = '1' and lq_addr_v(j) = '0' and lq_qjw(j) = '0' then
          if pa < 0 then pa := j; elsif ldist(j, lsq_head) < ldist(pa, lsq_head) then pa := j; end if;
        end if;
      end loop;
      if pa >= 0 then
        lq_addr(pa) <= (to_integer(unsigned(lq_vj(pa)(5 downto 0))) + lq_imm(pa)) mod 64;
        lq_addr_v(pa) <= '1';
      end if;
      -- a store is done (ready to commit) one edge after its address and data are both known
      for j in 0 to NLSQ-1 loop
        if lq_v(j) = '1' and lq_st(j) = '1' and lq_addr_v(j) = '1' and lq_qkw(j) = '0' and rob_done(lq_rob(j)) = '0' then rob_done(lq_rob(j)) <= '1'; end if;
      end loop;

      -- 4. commit the head of the ROB, in program order
      if do_commit then
        committed <= committed + 1;
        if rob_wr(head) = '1' then
          regfile(rob_reg(head)) <= rob_val(head);
          if regst_busy(rob_reg(head)) = '1' and regst_tag(rob_reg(head)) = head then regst_busy(rob_reg(head)) <= '0'; end if;
        end if;
        if rob_br(head) = '1' then branches <= branches + 1; end if;
        if rob_halt(head) = '1' then halted_i <= '1'; end if;
        if rob_mem(head) = '1' then
          if rob_st(head) = '1' then dmem(lq_addr(lsq_head)) <= lq_vk(lsq_head); stores <= stores + 1;
          else loads <= loads + 1; end if;
          lq_v(lsq_head) <= '0';  lq_addr_v(lsq_head) <= '0';
          if lsq_head = NLSQ - 1 then lsq_head <= 0; else lsq_head <= lsq_head + 1; end if;
        end if;
        rob_done(head) <= '0';
        if head = ROBN - 1 then head <= 0; else head <= head + 1; end if;
      end if;

      -- 5. issue: fetch the instruction at pc and follow the predicted path
      if do_issue then
        if halt_i then rob_done(tail) <= '1'; else rob_done(tail) <= '0'; end if;                 -- HALT needs no execution
        if alu_i or ld_i then rob_wr(tail) <= '1'; else rob_wr(tail) <= '0'; end if;
        if br_i then rob_br(tail) <= '1'; else rob_br(tail) <= '0'; end if;
        if halt_i then rob_halt(tail) <= '1'; else rob_halt(tail) <= '0'; end if;
        if mem_i then rob_mem(tail) <= '1'; else rob_mem(tail) <= '0'; end if;
        if st_i then rob_st(tail) <= '1'; else rob_st(tail) <= '0'; end if;
        if pred_taken then pbit := '1'; else pbit := '0'; end if;
        rob_pred(tail) <= pbit;  rob_tgt(tail) <= i_tgt;  rob_ft(tail) <= (pc + 1) mod 256; rob_pc(tail)<=pc;
        rob_reg(tail) <= i_rd;
        if tail = ROBN - 1 then tail <= 0; else tail <= tail + 1; end if;
        if alu_i or ld_i then regst_busy(i_rd) <= '1'; regst_tag(i_rd) <= tail; end if;
        if alu_i or br_i then
          rs_busy(free_rs) <= '1';  rs_exec(free_rs) <= '0';  rs_dest(free_rs) <= tail;
          if br_i then rs_op(free_rs) <= 3; else rs_op(free_rs) <= i_op; end if;
          rs_vj(free_rs) <= src_val(0);  rs_qjw(free_rs) <= src_wait(0);  rs_qjt(free_rs) <= src_tag(0);
          rs_vk(free_rs) <= src_val(1);  rs_qkw(free_rs) <= src_wait(1);  rs_qkt(free_rs) <= src_tag(1);
        end if;
        if mem_i then
          lq_unknown(lsq_tail)<=(others=>'0'); lq_v(lsq_tail) <= '1';  lq_addr_v(lsq_tail) <= '0';  lq_exec(lsq_tail) <= '0';  lq_imm(lsq_tail) <= i_imm;  lq_rob(lsq_tail) <= tail;
          if st_i then lq_st(lsq_tail) <= '1'; else lq_st(lsq_tail) <= '0'; end if;
          lq_vj(lsq_tail) <= src_val(0);  lq_qjw(lsq_tail) <= src_wait(0);  lq_qjt(lsq_tail) <= src_tag(0);
          lq_vk(lsq_tail) <= src_val(1);  lq_qkw(lsq_tail) <= src_wait(1);  lq_qkt(lsq_tail) <= src_tag(1);
          if lsq_tail = NLSQ - 1 then lsq_tail <= 0; else lsq_tail <= lsq_tail + 1; end if;
        end if;
        if pred_taken then pc <= i_tgt; else pc <= (pc + 1) mod 256; end if;
        if halt_i then fetch_stop <= '1'; end if;
      end if;
      nxt := count;
      if do_issue  then nxt := nxt + 1; end if;
      if do_commit then nxt := nxt - 1; end if;
      count <= nxt;
      nl := lsq_cnt;
      if do_issue and mem_i then nl := nl + 1; end if;
      if do_commit and rob_mem(head) = '1' then nl := nl - 1; end if;
      lsq_cnt <= nl;

      -- Selective suffix squash; older ROB and LSQ entries stay in flight.
      if recover_now and not flush_now then
        pc<=recover_pc; fetch_stop<='0'; tail<=(head+recover_keep) mod ROBN;
        nxt:=recover_keep; if do_commit then nxt:=nxt-1; end if; count<=nxt;
        squashed<=squashed+to_unsigned(count-recover_keep,32);
        if recover_branch then flushes<=flushes+1; else replays<=replays+1; end if;
        keep_lsq:=0;
        for j in 0 to NLSQ-1 loop
          if lq_v(j)='1' then
            if rdist(lq_rob(j),head)>=recover_keep then
              lq_v(j)<='0'; lq_addr_v(j)<='0'; lq_exec(j)<='0'; lq_qjw(j)<='0'; lq_qkw(j)<='0'; lq_unknown(j)<=(others=>'0');
            else keep_lsq:=keep_lsq+1; end if;
          end if;
        end loop;
        lsq_tail<=(lsq_head+keep_lsq) mod NLSQ;
        nl:=keep_lsq; if do_commit and rob_mem(head)='1' then nl:=nl-1; end if; lsq_cnt<=nl;
        for t in 0 to ROBN-1 loop if rdist(t,head)>=recover_keep and rdist(t,head)<count then rob_done(t)<='0'; end if; end loop;
        for i in 0 to NRS-1 loop
          if rs_busy(i)='1' and rdist(rs_dest(i),head)>=recover_keep then rs_busy(i)<='0'; rs_exec(i)<='0'; rs_qjw(i)<='0'; rs_qkw(i)<='0'; end if;
        end loop;
        for u in 0 to 2 loop
          if u_busy(u)='1' then
            if u=2 then tag_index:=lq_rob(u_rs(u)); else tag_index:=rs_dest(u_rs(u)); end if;
            if rdist(tag_index,head)>=recover_keep then u_busy(u)<='0'; u_done(u)<='0'; end if;
          end if;
        end loop;
        for r in 0 to NREG-1 loop
          found:=false; new_tag:=0;
          for off in 0 to ROBN-1 loop
            if off<recover_keep and not (do_commit and off=0) then
              tag_index:=(head+off) mod ROBN;
              if rob_wr(tag_index)='1' and rob_reg(tag_index)=r then found:=true; new_tag:=tag_index; end if;
            end if;
          end loop;
          if found then regst_busy(r)<='1'; regst_tag(r)<=new_tag; else regst_busy(r)<='0'; end if;
        end loop;
      end if;

      -- 6. misprediction: throw away everything younger than the branch (it is at the head, so that is everything else)
      if flush_now then
        flushes  <= flushes + 1;
        squashed <= squashed + (count - 1);
        if br_actual then pc <= rob_tgt(head); else pc <= rob_ft(head); end if;
        fetch_stop <= '0';
        head <= 0;  tail <= 0;  count <= 0;
        lsq_head <= 0;  lsq_tail <= 0;  lsq_cnt <= 0;
        rob_done <= (others => '0');
        rs_busy <= (others => '0');  rs_exec <= (others => '0');  rs_qjw <= (others => '0');  rs_qkw <= (others => '0');
        lq_v <= (others => '0');  lq_addr_v <= (others => '0');  lq_exec <= (others => '0');  lq_qjw <= (others => '0');  lq_qkw <= (others => '0');
        u_busy <= (others => '0');  u_done <= (others => '0');
        regst_busy <= (others => '0');
      end if;
    end if;
  end process;
end architecture;
