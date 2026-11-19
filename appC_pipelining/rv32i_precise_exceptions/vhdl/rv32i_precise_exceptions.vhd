-- Classic 5-stage RISC pipeline (IF ID EX MEM WB) for an RV32I subset:
--   add sub and or xor slt sll srl | addi andi ori xori slti slli srli | lui
--   lw sw | beq bne blt | jal jalr | ebreak (halts, for testbenches)
--
-- Hazard handling (Hennessy & Patterson, Appendix C):
--   * full forwarding EX/MEM -> EX and MEM/WB -> EX; register file is write-through
--   * 1-cycle stall for a load followed immediately by a consumer (load-use)
--   * branches/jumps resolve in EX: predict-not-taken, 2 wrong-path instructions flushed
-- Instruction/data memories are combinational-read 1-cycle models supplied by the testbench.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rv32i_pkg.all;

entity rv32i_precise_exceptions is
  port (
    clk, rst_n       : in  std_logic;
    imem_fault, dmem_fault, irq : in std_logic;
    store_addr, mepc, mcause : out std_logic_vector(31 downto 0);
    trap, fault_overlap : out std_logic;
    imem_addr        : out std_logic_vector(31 downto 0);
    imem_rdata       : in  std_logic_vector(31 downto 0);
    dmem_addr        : out std_logic_vector(31 downto 0);
    dmem_wdata       : out std_logic_vector(31 downto 0);
    dmem_we          : out std_logic;
    dmem_rdata       : in  std_logic_vector(31 downto 0);
    dbg_raddr        : in  std_logic_vector(4 downto 0);    -- debug read port on the register file
    dbg_rdata        : out std_logic_vector(31 downto 0);
    halted           : out std_logic;                       -- ebreak has retired
    stat_cycles      : out unsigned(31 downto 0);           -- all stats freeze once halted
    stat_retired     : out unsigned(31 downto 0);
    stat_load_stalls : out unsigned(31 downto 0);
    stat_flushes     : out unsigned(31 downto 0)            -- taken branches/jumps (2 cycles each)
  );
end entity;

architecture rtl of rv32i_precise_exceptions is
  subtype word is std_logic_vector(31 downto 0);
  type regfile_t is array (1 to 31) of word;
  signal regs : regfile_t := (others => (others => '0'));
  signal rf_we : std_logic;
  signal rf_waddr : std_logic_vector(4 downto 0);
  signal rf_wdata : word;

  signal pc_f : word := (others => '0');
  -- IF/ID
  signal valid_d : std_logic := '0';
  signal pc_d, instr_d : word := (others => '0');
  -- ID/EX
  signal valid_e, reg_write_e, mem_read_e, mem_write_e, alu_src_imm_e : std_logic := '0';
  signal is_branch_e, is_jal_e, is_jalr_e, is_lui_e, is_halt_e : std_logic := '0';
  signal funct3_e : std_logic_vector(2 downto 0) := "000";
  signal alu_op_e : alu_op_t := ALU_ADD;
  signal rd_e, rs1_e, rs2_e : std_logic_vector(4 downto 0) := (others => '0');
  signal pc_e, rs1_val_e, rs2_val_e, imm_e : word := (others => '0');
  -- EX/MEM
  signal valid_m, reg_write_m, mem_read_m, mem_write_m, is_halt_m : std_logic := '0';
  signal rd_m : std_logic_vector(4 downto 0) := (others => '0');
  signal alu_m, store_m : word := (others => '0');
  -- MEM/WB
  signal valid_w, reg_write_w, is_halt_w : std_logic := '0';
  signal rd_w : std_logic_vector(4 downto 0) := (others => '0');
  signal wb_w : word := (others => '0');
  signal halted_i : std_logic := '0';

  constant TRAP_VECTOR : word := x"00000080";
  signal fault_d, mret_e, mret_m, mret_w : std_logic := '0';
  signal csr_e, csr_m, csr_w, csr_cause_e, csr_cause_m, csr_cause_w : std_logic := '0';
  signal pc_m, pc_w, cause_e, cause_m, cause_w : word := (others=>'0');
  signal csr_value_m, csr_value_w, store_w, address_w : word := (others=>'0');
  signal mem_write_w, irq_pending, in_trap : std_logic := '0';
  signal is_mret_d, is_ecall_d, is_csr_d, illegal_d : std_logic;
  signal mem_fault, fault_w, return_w, halt_w, take_irq, serial_csr : std_logic;
  signal mem_cause, wb_cause : word;

  -- decode outputs
  signal reg_write_d, mem_read_d, mem_write_d, alu_src_imm_d, is_branch_d : std_logic;
  signal is_jal_d, is_jalr_d, is_lui_d, is_halt_d, uses_rs1_d, uses_rs2_d : std_logic;
  signal imm_d : word;
  signal alu_op_d : alu_op_t;
  -- execute
  signal fwd_a, fwd_b, ex_result, br_target : word;
  signal take_branch, redirect, load_use : std_logic;

  signal cycles, retired, stalls, flushes : unsigned(31 downto 0) := (others => '0');

  impure function rf_read(a : std_logic_vector(4 downto 0)) return word is
  begin
    if a = "00000" then return x"00000000";
    elsif rf_we = '1' and rf_waddr = a then return rf_wdata;       -- write-through
    else return regs(to_integer(unsigned(a)));
    end if;
  end function;

  function sext(v : std_logic_vector; n : natural) return word is
  begin return std_logic_vector(resize(signed(v), n)); end function;
begin
  imem_addr <= pc_f;
  halted <= halted_i;
  stat_cycles <= cycles;  stat_retired <= retired;  stat_load_stalls <= stalls;  stat_flushes <= flushes;
  dbg_rdata <= x"00000000" when dbg_raddr = "00000" else regs(to_integer(unsigned(dbg_raddr)));

  is_mret_d <= '1' when instr_d=x"30200073" else '0';
  is_ecall_d <= '1' when instr_d=x"00000073" else '0';
  is_csr_d <= '1' when (instr_d(31 downto 20)=x"341" or instr_d(31 downto 20)=x"342")
              and instr_d(14 downto 12)="001" and instr_d(6 downto 0)="1110011" else '0';
  ---------------------------------------------------------------- ID: decode
  decode : process (all)
    variable f3 : std_logic_vector(2 downto 0);
    variable is_sub : std_logic;
    variable opcode : std_logic_vector(6 downto 0);
    variable imm_i, imm_s, imm_b, imm_u, imm_j : word;
    variable op : alu_op_t;
  begin
    opcode := instr_d(6 downto 0);
    f3 := instr_d(14 downto 12);
    imm_i := sext(instr_d(31 downto 20), 32);
    imm_s := sext(instr_d(31 downto 25) & instr_d(11 downto 7), 32);
    imm_b := sext(instr_d(31) & instr_d(7) & instr_d(30 downto 25) & instr_d(11 downto 8) & '0', 32);
    imm_u := instr_d(31 downto 12) & x"000";
    imm_j := sext(instr_d(31) & instr_d(19 downto 12) & instr_d(20) & instr_d(30 downto 21) & '0', 32);
    case f3 is
      when "000"  => op := ALU_ADD;
      when "001"  => op := ALU_SLL;
      when "010"  => op := ALU_SLT;
      when "100"  => op := ALU_XOR;
      when "101"  => op := ALU_SRL;
      when "110"  => op := ALU_OR;
      when "111"  => op := ALU_AND;
      when others => op := ALU_ADD;
    end case;
    reg_write_d <= '0'; mem_read_d <= '0'; mem_write_d <= '0'; alu_src_imm_d <= '0'; is_branch_d <= '0';
    is_jal_d <= '0'; is_jalr_d <= '0'; is_lui_d <= '0'; is_halt_d <= '0'; uses_rs1_d <= '1'; uses_rs2_d <= '0';
    imm_d <= imm_i;  alu_op_d <= ALU_ADD;
    if opcode = OP_REG then
      reg_write_d <= '1'; uses_rs2_d <= '1';
      if f3 = "000" and instr_d(30) = '1' then alu_op_d <= ALU_SUB; else alu_op_d <= op; end if;
    elsif opcode = OP_IMM then
      reg_write_d <= '1'; alu_src_imm_d <= '1'; alu_op_d <= op;
    elsif opcode = OP_LOAD then
      reg_write_d <= '1'; mem_read_d <= '1'; alu_src_imm_d <= '1';
    elsif opcode = OP_STORE then
      mem_write_d <= '1'; alu_src_imm_d <= '1'; imm_d <= imm_s; uses_rs2_d <= '1';
    elsif opcode = OP_BRANCH then
      is_branch_d <= '1'; imm_d <= imm_b; uses_rs2_d <= '1';
    elsif opcode = OP_JAL then
      reg_write_d <= '1'; is_jal_d <= '1'; imm_d <= imm_j; uses_rs1_d <= '0';
    elsif opcode = OP_JALR then
      reg_write_d <= '1'; is_jalr_d <= '1'; alu_src_imm_d <= '1';
    elsif opcode = OP_LUI then
      reg_write_d <= '1'; is_lui_d <= '1'; imm_d <= imm_u; uses_rs1_d <= '0';
    else
      uses_rs1_d <= is_csr_d; reg_write_d <= is_csr_d;
      if instr_d = INSN_EBREAK then is_halt_d <= '1'; end if;
    end if;
    illegal_d<='0';
    case opcode is
      when OP_REG =>
        if f3="011" or (instr_d(31 downto 25)/="0000000" and
           not (f3="000" and instr_d(31 downto 25)="0100000")) then illegal_d<='1'; end if;
      when OP_IMM =>
        if f3="011" or ((f3="001" or f3="101") and instr_d(31 downto 25)/="0000000") then illegal_d<='1'; end if;
      when OP_LOAD | OP_STORE => if f3/="010" then illegal_d<='1'; end if;
      when OP_BRANCH => if f3/="000" and f3/="001" and f3/="100" then illegal_d<='1'; end if;
      when OP_JALR => if f3/="000" then illegal_d<='1'; end if;
      when OP_JAL | OP_LUI => null;
      when others =>
        if is_mret_d='0' and is_ecall_d='0' and is_csr_d='0' and instr_d/=INSN_EBREAK then illegal_d<='1'; end if;
    end case;
  end process;

  ---------------------------------------------------------------- EX: forward, ALU, branch
  execute : process (all)
    variable a, b, alub, y : word;
    variable sa, sb : signed(31 downto 0);
    variable sh : natural range 0 to 31;
    variable tb : std_logic;
  begin
    a := rs1_val_e;  b := rs2_val_e;
    if reg_write_w = '1' and valid_w = '1' and rd_w /= "00000" and rd_w = rs1_e then a := wb_w; end if;
    if reg_write_w = '1' and valid_w = '1' and rd_w /= "00000" and rd_w = rs2_e then b := wb_w; end if;
    if reg_write_m = '1' and valid_m = '1' and rd_m /= "00000" and rd_m = rs1_e then a := alu_m; end if;
    if reg_write_m = '1' and valid_m = '1' and rd_m /= "00000" and rd_m = rs2_e then b := alu_m; end if;
    fwd_a <= a;  fwd_b <= b;
    if alu_src_imm_e = '1' then alub := imm_e; else alub := b; end if;
    sa := signed(a);  sb := signed(alub);
    sh := to_integer(unsigned(alub(4 downto 0)));
    case alu_op_e is
      when ALU_ADD => y := std_logic_vector(unsigned(a) + unsigned(alub));
      when ALU_SUB => y := std_logic_vector(unsigned(a) - unsigned(alub));
      when ALU_AND => y := a and alub;
      when ALU_OR  => y := a or alub;
      when ALU_XOR => y := a xor alub;
      when ALU_SLT => y := (others => '0'); if sa < sb then y(0) := '1'; end if;
      when ALU_SLL => y := std_logic_vector(shift_left(unsigned(a), sh));
      when ALU_SRL => y := std_logic_vector(shift_right(unsigned(a), sh));
    end case;
    if csr_e='1' then
      if csr_cause_e='1' then ex_result<=mcause; else ex_result<=mepc; end if;
    elsif is_jal_e = '1' or is_jalr_e = '1' then
      ex_result <= std_logic_vector(unsigned(pc_e) + 4);
    elsif is_lui_e = '1' then
      ex_result <= imm_e;
    else
      ex_result <= y;
    end if;
    -- branch condition
    tb := '0';
    case funct3_e is
      when "000"  => if a = b then tb := '1'; end if;
      when "001"  => if a /= b then tb := '1'; end if;
      when "100"  => if signed(a) < signed(b) then tb := '1'; end if;
      when others => tb := '0';
    end case;
    take_branch <= tb;
    if is_jalr_e = '1' then
      br_target <= std_logic_vector(unsigned(a) + unsigned(imm_e)) and x"FFFFFFFE";
    else
      br_target <= std_logic_vector(unsigned(pc_e) + unsigned(imm_e));
    end if;
  end process;

  redirect <= '1' when valid_e = '1' and cause_e=x"00000000" and ((is_branch_e = '1' and take_branch = '1') or is_jal_e = '1' or is_jalr_e = '1') else '0';

  load_use <= '1' when valid_d = '1' and valid_e = '1' and mem_read_e = '1' and rd_e /= "00000" and
                       ((uses_rs1_d = '1' and instr_d(19 downto 15) = rd_e) or
                        (uses_rs2_d = '1' and instr_d(24 downto 20) = rd_e)) else '0';

  ---------------------------------------------------------------- MEM / WB
  dmem_addr  <= alu_m;
  mem_fault <= '1' when valid_m='1' and cause_m=x"00000000" and (mem_read_m='1' or mem_write_m='1')
               and (dmem_fault='1' or alu_m(1 downto 0)/="00") else '0';
  mem_cause <= x"00000007" when dmem_fault='1' and mem_write_m='1' else
               x"00000005" when dmem_fault='1' else x"00000006" when mem_write_m='1' else x"00000004";
  wb_cause <= mem_cause when mem_fault='1' else cause_m;
  fault_w <= '1' when valid_w='1' and cause_w/=x"00000000" else '0';
  return_w <= valid_w and not fault_w and mret_w;
  halt_w <= valid_w and is_halt_w and not fault_w;
  take_irq <= (irq or irq_pending) and not in_trap and not (valid_d or valid_e or valid_m or valid_w);
  serial_csr <= (valid_e and (csr_e or mret_e)) or (valid_m and (csr_m or mret_m)) or
                (valid_w and (csr_w or mret_w));
  store_addr <= address_w;
  dmem_wdata <= store_w;
  dmem_we <= valid_w and mem_write_w and not fault_w and not halted_i;
  fault_overlap <= '1' when mem_fault='1' and valid_e='1' and cause_e/=x"00000000" else '0';
  rf_we <= valid_w and reg_write_w and not halted_i and not fault_w;
  rf_waddr   <= rd_w;
  rf_wdata   <= wb_w;

  ---------------------------------------------------------------- sequential logic
  seq : process (clk, rst_n)
  begin
    if rst_n = '0' then
      mepc<=(others=>'0'); mcause<=(others=>'0'); trap<='0'; in_trap<='0'; irq_pending<='0';
      mret_e<='0'; mret_m<='0'; mret_w<='0'; csr_e<='0'; csr_m<='0'; csr_w<='0';
      csr_cause_e<='0'; csr_cause_m<='0'; csr_cause_w<='0';
      cause_e<=(others=>'0'); cause_m<=(others=>'0'); cause_w<=(others=>'0');
      fault_d<='0'; mem_write_w<='0'; pc_m<=(others=>'0'); pc_w<=(others=>'0');
      csr_value_m<=(others=>'0'); csr_value_w<=(others=>'0'); store_w<=(others=>'0'); address_w<=(others=>'0');
      pc_f <= (others => '0');
      valid_d <= '0'; valid_e <= '0'; valid_m <= '0'; valid_w <= '0'; halted_i <= '0';
      reg_write_e <= '0'; mem_read_e <= '0'; mem_write_e <= '0'; is_branch_e <= '0'; is_jal_e <= '0';
      is_jalr_e <= '0'; is_lui_e <= '0'; is_halt_e <= '0';
      reg_write_m <= '0'; mem_read_m <= '0'; mem_write_m <= '0'; is_halt_m <= '0';
      reg_write_w <= '0'; is_halt_w <= '0';
      cycles <= (others => '0'); retired <= (others => '0'); stalls <= (others => '0'); flushes <= (others => '0');
      regs <= (others => (others => '0'));
    elsif rising_edge(clk) and halted_i='0' then
      trap<='0';
      if irq='1' then irq_pending<='1'; end if;
      if valid_w='1' and csr_w='1' and fault_w='0' then
        if csr_cause_w='1' then mcause<=csr_value_w; else mepc<=csr_value_w and x"fffffffc"; end if;
      end if;
      -- register file write
      if rf_we = '1' and rf_waddr /= "00000" then regs(to_integer(unsigned(rf_waddr))) <= rf_wdata; end if;
      -- IF
      if redirect = '1' then
        pc_f <= br_target;  valid_d <= '0';
      elsif load_use='0' and serial_csr='0' then
        if (irq='1' or irq_pending='1') and in_trap='0' then valid_d<='0';
        else
          pc_f<=std_logic_vector(unsigned(pc_f)+4);
          pc_d<=pc_f; instr_d<=imem_rdata; valid_d<='1';
          if imem_fault='1' or pc_f(1 downto 0)/="00" then fault_d<='1'; else fault_d<='0'; end if;
        end if;
      end if;
      -- ID -> EX (bubble on stall / flush)
      if redirect='1' or load_use='1' or serial_csr='1' or valid_d='0' then
        cause_e<=(others=>'0'); csr_e<='0'; mret_e<='0';
        valid_e <= '0'; reg_write_e <= '0'; mem_read_e <= '0'; mem_write_e <= '0'; is_branch_e <= '0';
        is_jal_e <= '0'; is_jalr_e <= '0'; is_lui_e <= '0'; is_halt_e <= '0';
      else
        if fault_d='1' then cause_e<=x"00000001";
        elsif illegal_d='1' then cause_e<=x"00000002";
        elsif is_ecall_d='1' then cause_e<=x"0000000b";
        else cause_e<=(others=>'0'); end if;
        csr_e<=is_csr_d; mret_e<=is_mret_d; csr_cause_e<=not instr_d(20);
        valid_e <= '1'; reg_write_e <= reg_write_d; mem_read_e <= mem_read_d; mem_write_e <= mem_write_d;
        alu_src_imm_e <= alu_src_imm_d; is_branch_e <= is_branch_d; is_jal_e <= is_jal_d;
        is_jalr_e <= is_jalr_d; is_lui_e <= is_lui_d; is_halt_e <= is_halt_d; alu_op_e <= alu_op_d;
        funct3_e <= instr_d(14 downto 12); rd_e <= instr_d(11 downto 7);
        rs1_e <= instr_d(19 downto 15); rs2_e <= instr_d(24 downto 20);
        pc_e <= pc_d; imm_e <= imm_d;
        rs1_val_e <= rf_read(instr_d(19 downto 15)); rs2_val_e <= rf_read(instr_d(24 downto 20));
      end if;
      -- EX -> MEM
      valid_m <= valid_e; reg_write_m <= reg_write_e; mem_read_m <= mem_read_e;
      mem_write_m <= mem_write_e; is_halt_m <= is_halt_e; rd_m <= rd_e;
      alu_m <= ex_result; store_m <= fwd_b;
      pc_m<=pc_e; cause_m<=cause_e; mret_m<=mret_e;
      csr_m<=csr_e; csr_cause_m<=csr_cause_e; csr_value_m<=fwd_a;
      -- MEM -> WB
      valid_w <= valid_m; reg_write_w <= reg_write_m; is_halt_w <= is_halt_m; rd_w <= rd_m;
      if mem_read_m='1' then
        if dmem_we='1' and store_addr=alu_m then wb_w<=store_w; else wb_w<=dmem_rdata; end if;
      else wb_w<=alu_m; end if;
      cause_w<=wb_cause; pc_w<=pc_m; mret_w<=mret_m;
      csr_w<=csr_m; csr_cause_w<=csr_cause_m; csr_value_w<=csr_value_m;
      mem_write_w<=mem_write_m; address_w<=alu_m; store_w<=store_m;
      if fault_w='1' or take_irq='1' or return_w='1' or halt_w='1' then
        valid_d<='0'; valid_e<='0'; valid_m<='0'; valid_w<='0';
        if fault_w='1' or take_irq='1' then
          if fault_w='1' then mepc<=pc_w; mcause<=cause_w;
          else mepc<=pc_f; mcause<=x"8000000b"; irq_pending<='0'; end if;
          pc_f<=TRAP_VECTOR; trap<='1'; in_trap<='1';
        elsif return_w='1' then pc_f<=mepc; in_trap<='0'; end if;
      end if;
      -- statistics / halt
      if halt_w='1' then halted_i<='1'; end if;
      if halted_i = '0' then
        cycles <= cycles + 1;
        if valid_w='1' and fault_w='0' then retired <= retired + 1; end if;
        if load_use = '1' then stalls  <= stalls + 1;  end if;
        if redirect = '1' then flushes <= flushes + 1; end if;
      end if;
    end if;
  end process;
end architecture;
