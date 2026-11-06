-- The Appendix C five-stage pipeline for the DLX / MIPS family, with branches resolved in ID.
--
--   XLEN = 32 : DLX-style 32-bit machine (MIPS32 encodings: ADD SUB ... ADDI LW SW)         -- 1st/2nd editions' ISA
--   XLEN = 64 : MIPS64 (DADDU DSUBU DSLL DSRL DADDIU LD SD; PC stays 32 bits)                -- 3rd-5th editions' ISA
-- Common: 32 registers with r0 = 0, formats R/I/J, no branch delay slot, ADD-family and logic ops,
--   AND OR XOR SLT | ANDI ORI LUI | BEQ BNE | J JAL JR | BREAK (halts, for testbenches).
--   Branch offsets are in words, relative to PC+4 (MIPS convention).  BEQZ/BNEZ are BEQ/BNE against r0.
--
-- Hazards:
--   * EX forwarding from EX/MEM and MEM/WB; register file is write-through.
--   * load-use: 1 stall.
--   * control: BEQ/BNE/J/JAL/JR are resolved in ID (a comparator lives there), so a taken transfer costs ONE
--     cycle (the sequentially fetched instruction is dropped).  The price is a new data hazard:
--       - branch operand produced by the instruction just ahead (in EX)      -> stall until it reaches MEM,
--         then forward its ALU result into ID                                 (1 stall)
--       - branch operand is a load that is now in MEM                        -> stall until it reaches WB   (+1)
--       - (a load in EX is first handled by the load-use stall, then the rule above)
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mips_pipeline is
  generic (XLEN : positive := 32);                  -- 32 = DLX / MIPS32 flavor, 64 = MIPS64 flavor
  port (
    clk, rst_n         : in  std_logic;
    imem_addr          : out std_logic_vector(31 downto 0);
    imem_rdata         : in  std_logic_vector(31 downto 0);
    dmem_addr          : out std_logic_vector(XLEN-1 downto 0);
    dmem_wdata         : out std_logic_vector(XLEN-1 downto 0);
    dmem_we            : out std_logic;
    dmem_rdata         : in  std_logic_vector(XLEN-1 downto 0);
    dbg_raddr          : in  std_logic_vector(4 downto 0);
    dbg_rdata          : out std_logic_vector(XLEN-1 downto 0);
    halted             : out std_logic;
    stat_cycles        : out unsigned(31 downto 0);
    stat_retired       : out unsigned(31 downto 0);
    stat_load_stalls   : out unsigned(31 downto 0);   -- load-use
    stat_branch_stalls : out unsigned(31 downto 0);   -- branch operand not ready
    stat_flushes       : out unsigned(31 downto 0)    -- taken branches / jumps (1 cycle each)
  );
end entity;

architecture rtl of mips_pipeline is
  constant IS64 : boolean := (XLEN = 64);
  subtype word is std_logic_vector(XLEN-1 downto 0);
  subtype code6 is std_logic_vector(5 downto 0);
  function sel(b : boolean; x, y : natural) return code6 is
  begin
    if b then return code6(to_unsigned(x, 6)); else return code6(to_unsigned(y, 6)); end if;
  end function;
  constant F_ADD   : code6 := sel(IS64, 16#2D#, 16#20#);     -- DADDU / ADD
  constant F_SUB   : code6 := sel(IS64, 16#2F#, 16#22#);     -- DSUBU / SUB
  constant F_SLL   : code6 := sel(IS64, 16#38#, 16#00#);     -- DSLL  / SLL
  constant F_SRL   : code6 := sel(IS64, 16#3A#, 16#02#);     -- DSRL  / SRL
  constant O_ADDI  : code6 := sel(IS64, 16#19#, 16#08#);     -- DADDIU / ADDI
  constant O_LOAD  : code6 := sel(IS64, 16#37#, 16#23#);     -- LD / LW
  constant O_STORE : code6 := sel(IS64, 16#3F#, 16#2B#);     -- SD / SW

  type alu_t is (A_ADD, A_SUB, A_AND, A_OR, A_XOR, A_SLT, A_SLL, A_SRL, A_PASSB);

  type regfile_t is array (1 to 31) of word;
  signal regs : regfile_t := (others => (others => '0'));
  signal rf_we : std_logic;
  signal rf_waddr : std_logic_vector(4 downto 0);
  signal rf_wdata : word;

  signal pc_f : std_logic_vector(31 downto 0) := (others => '0');
  signal valid_d : std_logic := '0';
  signal pc_d, instr_d : std_logic_vector(31 downto 0) := (others => '0');
  signal valid_e, reg_write_e, mem_read_e, mem_write_e, use_imm_e, is_jal_e, is_halt_e : std_logic := '0';
  signal alu_op_e : alu_t := A_ADD;
  signal dest_e, ra_e, rb_e : std_logic_vector(4 downto 0) := (others => '0');
  signal pc4_e : std_logic_vector(31 downto 0) := (others => '0');
  signal va_e, vb_e, imm_e : word := (others => '0');
  signal valid_m, reg_write_m, mem_read_m, mem_write_m, is_halt_m : std_logic := '0';
  signal dest_m : std_logic_vector(4 downto 0) := (others => '0');
  signal alu_m, store_m : word := (others => '0');
  signal valid_w, reg_write_w, is_halt_w : std_logic := '0';
  signal dest_w : std_logic_vector(4 downto 0) := (others => '0');
  signal wb_w : word := (others => '0');
  signal halted_i : std_logic := '0';

  -- decode results
  signal reg_write_d, mem_read_d, mem_write_d, use_imm_d, is_branch_d, is_bne_d, is_j_d, is_jal_d, is_jr_d, is_halt_d : std_logic;
  signal use_a_d, use_b_d : std_logic;
  signal src_a_d, src_b_d, dest_d : std_logic_vector(4 downto 0);
  signal imm_d : word;
  signal alu_op_d : alu_t;
  -- hazards / control
  signal load_use, br_hazard, stall, redirect : std_logic;
  signal ida, idb : word;
  signal target : std_logic_vector(31 downto 0);
  signal pc4_d : std_logic_vector(31 downto 0);
  -- execute
  signal fa, fb, ex_result : word;

  signal cycles, retired, lstalls, bstalls, flushes : unsigned(31 downto 0) := (others => '0');

  -- Pure on purpose: every signal it needs is an argument, so a process(all) that calls it is sensitive to all of them.
  -- (An impure function that reads rf_wdata internally would NOT add rf_wdata to the sensitivity list.)
  function rf_read(a : std_logic_vector(4 downto 0); we : std_logic; wa : std_logic_vector(4 downto 0);
                   wd : word; rg : regfile_t) return word is
  begin
    if is_x(a) or a = "00000" then return (word'range => '0');      -- r0, or not yet driven at time 0
    elsif we = '1' and wa = a then return wd;                       -- write-through
    else return rg(to_integer(unsigned(a)));
    end if;
  end function;
begin
  imem_addr <= pc_f;  halted <= halted_i;
  stat_cycles <= cycles;  stat_retired <= retired;  stat_load_stalls <= lstalls;
  stat_branch_stalls <= bstalls;  stat_flushes <= flushes;
  dbg_rdata <= (word'range => '0') when dbg_raddr = "00000" else regs(to_integer(unsigned(dbg_raddr)));
  pc4_d <= std_logic_vector(unsigned(pc_d) + 4);

  ---------------------------------------------------------------- ID: decode
  decode : process (all)
    variable opcode, funct : code6;
    variable imm16 : std_logic_vector(15 downto 0);
    variable sx, zx, lu : word;
    variable lu32 : std_logic_vector(31 downto 0);
  begin
    opcode := instr_d(31 downto 26);  funct := instr_d(5 downto 0);  imm16 := instr_d(15 downto 0);
    sx := std_logic_vector(resize(signed(imm16), XLEN));
    zx := std_logic_vector(resize(unsigned(imm16), XLEN));
    lu32 := imm16 & x"0000";
    lu := std_logic_vector(resize(signed(lu32), XLEN));
    reg_write_d <= '0'; mem_read_d <= '0'; mem_write_d <= '0'; use_imm_d <= '0'; is_branch_d <= '0'; is_bne_d <= '0';
    is_j_d <= '0'; is_jal_d <= '0'; is_jr_d <= '0'; is_halt_d <= '0'; use_a_d <= '0'; use_b_d <= '0';
    src_a_d <= instr_d(25 downto 21);  src_b_d <= instr_d(20 downto 16);  dest_d <= instr_d(15 downto 11);
    imm_d <= sx;  alu_op_d <= A_ADD;
    if opcode = "000000" then                                        -- R-type
      if    funct = F_ADD      then reg_write_d <= '1'; use_a_d <= '1'; use_b_d <= '1'; alu_op_d <= A_ADD;
      elsif funct = F_SUB      then reg_write_d <= '1'; use_a_d <= '1'; use_b_d <= '1'; alu_op_d <= A_SUB;
      elsif funct = "100100"   then reg_write_d <= '1'; use_a_d <= '1'; use_b_d <= '1'; alu_op_d <= A_AND;
      elsif funct = "100101"   then reg_write_d <= '1'; use_a_d <= '1'; use_b_d <= '1'; alu_op_d <= A_OR;
      elsif funct = "100110"   then reg_write_d <= '1'; use_a_d <= '1'; use_b_d <= '1'; alu_op_d <= A_XOR;
      elsif funct = "101010"   then reg_write_d <= '1'; use_a_d <= '1'; use_b_d <= '1'; alu_op_d <= A_SLT;
      elsif funct = F_SLL then
        reg_write_d <= '1'; use_a_d <= '1'; src_a_d <= instr_d(20 downto 16); use_imm_d <= '1';
        imm_d <= std_logic_vector(resize(unsigned(instr_d(10 downto 6)), XLEN)); alu_op_d <= A_SLL;
      elsif funct = F_SRL then
        reg_write_d <= '1'; use_a_d <= '1'; src_a_d <= instr_d(20 downto 16); use_imm_d <= '1';
        imm_d <= std_logic_vector(resize(unsigned(instr_d(10 downto 6)), XLEN)); alu_op_d <= A_SRL;
      elsif funct = "001000"   then is_jr_d <= '1'; use_a_d <= '1';
      elsif funct = "001101"   then is_halt_d <= '1';                -- BREAK
      end if;
    elsif opcode = O_ADDI   then reg_write_d <= '1'; use_a_d <= '1'; use_imm_d <= '1'; dest_d <= instr_d(20 downto 16); alu_op_d <= A_ADD;
    elsif opcode = "001100" then reg_write_d <= '1'; use_a_d <= '1'; use_imm_d <= '1'; dest_d <= instr_d(20 downto 16); alu_op_d <= A_AND; imm_d <= zx;
    elsif opcode = "001101" then reg_write_d <= '1'; use_a_d <= '1'; use_imm_d <= '1'; dest_d <= instr_d(20 downto 16); alu_op_d <= A_OR;  imm_d <= zx;
    elsif opcode = "001111" then reg_write_d <= '1'; use_imm_d <= '1'; dest_d <= instr_d(20 downto 16); alu_op_d <= A_PASSB; imm_d <= lu;
    elsif opcode = O_LOAD   then reg_write_d <= '1'; mem_read_d <= '1'; use_a_d <= '1'; use_imm_d <= '1'; dest_d <= instr_d(20 downto 16);
    elsif opcode = O_STORE  then mem_write_d <= '1'; use_a_d <= '1'; use_b_d <= '1'; use_imm_d <= '1';
    elsif opcode = "000100" then is_branch_d <= '1'; use_a_d <= '1'; use_b_d <= '1';
    elsif opcode = "000101" then is_branch_d <= '1'; is_bne_d <= '1'; use_a_d <= '1'; use_b_d <= '1';
    elsif opcode = "000010" then is_j_d <= '1';
    elsif opcode = "000011" then is_jal_d <= '1'; reg_write_d <= '1'; dest_d <= "11111";
    end if;
  end process;

  ---------------------------------------------------------------- ID: hazards and early branch resolution
  hazards : process (all)
    variable ctrl, ea, eb, ma, mb, lu, bh, taken : boolean;
    variable a, b : word;
    variable tgt : std_logic_vector(31 downto 0);
    variable br : unsigned(31 downto 0);
  begin
    ctrl := is_branch_d = '1' or is_jr_d = '1';
    ea := use_a_d = '1' and src_a_d = dest_e;   eb := use_b_d = '1' and src_b_d = dest_e;
    ma := use_a_d = '1' and src_a_d = dest_m;   mb := use_b_d = '1' and src_b_d = dest_m;
    lu := valid_d = '1' and valid_e = '1' and mem_read_e = '1' and dest_e /= "00000" and (ea or eb);
    bh := valid_d = '1' and ctrl and
          ((valid_e = '1' and reg_write_e = '1' and dest_e /= "00000" and (ea or eb)) or            -- producer in EX
           (valid_m = '1' and mem_read_m = '1' and dest_m /= "00000" and (ma or mb)));              -- load in MEM
    if lu then load_use <= '1'; else load_use <= '0'; end if;
    if bh then br_hazard <= '1'; else br_hazard <= '0'; end if;
    if lu or bh then stall <= '1'; else stall <= '0'; end if;

    a := rf_read(src_a_d, rf_we, rf_waddr, rf_wdata, regs);  b := rf_read(src_b_d, rf_we, rf_waddr, rf_wdata, regs);                  -- branch operands, forwarded from MEM
    if valid_m = '1' and reg_write_m = '1' and mem_read_m = '0' and dest_m /= "00000" and dest_m = src_a_d then a := alu_m; end if;
    if valid_m = '1' and reg_write_m = '1' and mem_read_m = '0' and dest_m /= "00000" and dest_m = src_b_d then b := alu_m; end if;
    ida <= a;  idb <= b;
    if is_bne_d = '1' then taken := a /= b; else taken := a = b; end if;

    br  := unsigned(pc4_d) + shift_left(unsigned(resize(signed(instr_d(15 downto 0)), 32)), 2);
    if is_jr_d = '1' then tgt := a(31 downto 0);
    elsif is_j_d = '1' or is_jal_d = '1' then tgt := pc4_d(31 downto 28) & instr_d(25 downto 0) & "00";
    else tgt := std_logic_vector(br);
    end if;
    target <= tgt;
    if valid_d = '1' and not (lu or bh) and ((is_branch_d = '1' and taken) or is_j_d = '1' or is_jal_d = '1' or is_jr_d = '1') then
      redirect <= '1';
    else
      redirect <= '0';
    end if;
  end process;

  ---------------------------------------------------------------- EX: forwarding and ALU
  execute : process (all)
    variable a, b, ob, y : word;
    variable sh : natural range 0 to 63;
  begin
    a := va_e;  b := vb_e;
    if reg_write_w = '1' and valid_w = '1' and dest_w /= "00000" and dest_w = ra_e then a := wb_w; end if;
    if reg_write_w = '1' and valid_w = '1' and dest_w /= "00000" and dest_w = rb_e then b := wb_w; end if;
    if reg_write_m = '1' and valid_m = '1' and dest_m /= "00000" and dest_m = ra_e then a := alu_m; end if;
    if reg_write_m = '1' and valid_m = '1' and dest_m /= "00000" and dest_m = rb_e then b := alu_m; end if;
    fa <= a;  fb <= b;
    if use_imm_e = '1' then ob := imm_e; else ob := b; end if;
    sh := to_integer(unsigned(ob(5 downto 0)));
    case alu_op_e is
      when A_ADD   => y := std_logic_vector(unsigned(a) + unsigned(ob));
      when A_SUB   => y := std_logic_vector(unsigned(a) - unsigned(ob));
      when A_AND   => y := a and ob;
      when A_OR    => y := a or ob;
      when A_XOR   => y := a xor ob;
      when A_SLT   => y := (others => '0'); if signed(a) < signed(ob) then y(0) := '1'; end if;
      when A_SLL   => y := std_logic_vector(shift_left(unsigned(a), sh));
      when A_SRL   => y := std_logic_vector(shift_right(unsigned(a), sh));
      when A_PASSB => y := ob;
    end case;
    if is_jal_e = '1' then ex_result <= std_logic_vector(resize(unsigned(pc4_e), XLEN)); else ex_result <= y; end if;
  end process;

  ---------------------------------------------------------------- MEM / WB
  dmem_addr  <= alu_m;
  dmem_wdata <= store_m;
  dmem_we    <= valid_m and mem_write_m;
  rf_we      <= valid_w and reg_write_w and not halted_i;
  rf_waddr   <= dest_w;
  rf_wdata   <= wb_w;

  seq : process (clk, rst_n)
  begin
    if rst_n = '0' then
      pc_f <= (others => '0');
      valid_d <= '0'; valid_e <= '0'; valid_m <= '0'; valid_w <= '0'; halted_i <= '0';
      reg_write_e <= '0'; mem_read_e <= '0'; mem_write_e <= '0'; is_jal_e <= '0'; is_halt_e <= '0';
      reg_write_m <= '0'; mem_read_m <= '0'; mem_write_m <= '0'; is_halt_m <= '0'; reg_write_w <= '0'; is_halt_w <= '0';
      dest_e <= (others => '0'); dest_m <= (others => '0'); dest_w <= (others => '0');
      cycles <= (others => '0'); retired <= (others => '0'); lstalls <= (others => '0');
      bstalls <= (others => '0'); flushes <= (others => '0');
      regs <= (others => (others => '0'));
    elsif rising_edge(clk) then
      if rf_we = '1' and rf_waddr /= "00000" then regs(to_integer(unsigned(rf_waddr))) <= rf_wdata; end if;
      -- IF
      if redirect = '1' then
        pc_f <= target;  valid_d <= '0';
      elsif stall = '0' then
        pc_f <= std_logic_vector(unsigned(pc_f) + 4);  pc_d <= pc_f;  instr_d <= imem_rdata;  valid_d <= '1';
      end if;
      -- ID -> EX
      if stall = '1' or valid_d = '0' then
        valid_e <= '0'; reg_write_e <= '0'; mem_read_e <= '0'; mem_write_e <= '0'; is_jal_e <= '0'; is_halt_e <= '0';
        dest_e <= (others => '0');
      else
        valid_e <= '1'; reg_write_e <= reg_write_d; mem_read_e <= mem_read_d; mem_write_e <= mem_write_d;
        use_imm_e <= use_imm_d; is_jal_e <= is_jal_d; is_halt_e <= is_halt_d; alu_op_e <= alu_op_d;
        dest_e <= dest_d;
        if use_a_d = '1' then ra_e <= src_a_d; else ra_e <= "00000"; end if;
        if use_b_d = '1' then rb_e <= src_b_d; else rb_e <= "00000"; end if;
        pc4_e <= pc4_d;  imm_e <= imm_d;  va_e <= rf_read(src_a_d, rf_we, rf_waddr, rf_wdata, regs);  vb_e <= rf_read(src_b_d, rf_we, rf_waddr, rf_wdata, regs);
      end if;
      -- EX -> MEM
      valid_m <= valid_e; reg_write_m <= reg_write_e; mem_read_m <= mem_read_e; mem_write_m <= mem_write_e;
      is_halt_m <= is_halt_e; dest_m <= dest_e; alu_m <= ex_result; store_m <= fb;
      -- MEM -> WB
      valid_w <= valid_m; reg_write_w <= reg_write_m; is_halt_w <= is_halt_m; dest_w <= dest_m;
      if mem_read_m = '1' then wb_w <= dmem_rdata; else wb_w <= alu_m; end if;
      -- statistics / halt
      if valid_w = '1' and is_halt_w = '1' then halted_i <= '1'; end if;
      if halted_i = '0' then
        cycles <= cycles + 1;
        if valid_w = '1' then retired <= retired + 1; end if;
        if valid_d = '1' and load_use = '1' then lstalls <= lstalls + 1;
        elsif valid_d = '1' and br_hazard = '1' then bstalls <= bstalls + 1;
        end if;
        if redirect = '1' then flushes <= flushes + 1; end if;
      end if;
    end if;
  end process;
end architecture;
