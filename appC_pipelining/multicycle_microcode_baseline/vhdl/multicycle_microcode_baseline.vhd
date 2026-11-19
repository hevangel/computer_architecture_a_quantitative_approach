library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.rv32i_pkg.all;

entity multicycle_microcode_baseline is
    generic (MICROCODE : boolean := false);
    port (
        clk, rst_n : in std_logic;
        imem_addr : out std_logic_vector(31 downto 0);
        imem_rdata : in std_logic_vector(31 downto 0);
        dmem_addr, dmem_wdata : out std_logic_vector(31 downto 0);
        dmem_we : out std_logic;
        dmem_rdata : in std_logic_vector(31 downto 0);
        dbg_raddr : in std_logic_vector(4 downto 0);
        dbg_rdata : out std_logic_vector(31 downto 0);
        halted : out std_logic;
        cycles, retired : out unsigned(31 downto 0)
    );
end entity;
architecture rtl of multicycle_microcode_baseline is
    subtype word is unsigned(31 downto 0);
    subtype control_word is std_logic_vector(8 downto 0);
    type register_file is array(0 to 31) of word;
    type microprogram is array(0 to 4) of control_word;
    constant FETCH : natural := 0;
    constant DECODE : natural := 1;
    constant EXECUTE : natural := 2;
    constant MEMORY : natural := 3;
    constant FINISH : natural := 4;
    constant ROM : microprogram := (
        "000100001",
        "001000010",
        "110000100",
        "010001000",
        "000010000"
    );
    signal fsm_state, micro_pc, next_fsm, next_micro : natural range 0 to 4 := FETCH;
    signal control : std_logic_vector(4 downto 0);
    signal regs : register_file;
    signal pc, operand_a, operand_b, value, next_pc : word;
    signal instruction : std_logic_vector(31 downto 0);
    signal op : std_logic_vector(6 downto 0);
    signal fn : std_logic_vector(2 downto 0);
    function sign_extend(v : std_logic_vector) return word is
    begin return unsigned(resize(signed(v),32)); end;
begin
    op<=instruction(6 downto 0);
    fn<=instruction(14 downto 12);
    imem_addr<=std_logic_vector(pc);
    dmem_addr<=std_logic_vector(value); dmem_wdata<=std_logic_vector(operand_b);
    dmem_we<='1' when rst_n='1' and halted='0' and control(FINISH)='1' and op=OP_STORE else '0';
    dbg_rdata<=std_logic_vector(regs(to_integer(unsigned(dbg_raddr))));
    process(all)
        variable uword : control_word;
        variable enable : std_logic_vector(4 downto 0);
    begin
        enable:=(others=>'0');
        next_fsm<=FETCH;
        uword:=ROM(micro_pc);
        if uword(8)='1' and op=OP_LOAD then next_micro<=MEMORY;
        else next_micro<=to_integer(unsigned(uword(7 downto 5))); end if;
        if MICROCODE then enable:=uword(4 downto 0);
        else
            enable(fsm_state):='1';
            case fsm_state is
                when FETCH => next_fsm<=DECODE;
                when DECODE => next_fsm<=EXECUTE;
                when EXECUTE => if op=OP_LOAD then next_fsm<=MEMORY; else next_fsm<=FINISH; end if;
                when MEMORY => next_fsm<=FINISH;
                when others => next_fsm<=FETCH;
            end case;
        end if;
        control<=enable;
    end process;
    process(clk)
        variable ri, rs : word;
        variable destination, shift_amount : natural;
    begin
        if rising_edge(clk) then
            if rst_n='0' then
                fsm_state<=FETCH; micro_pc<=FETCH; regs<=(others=>(others=>'0'));
                pc<=(others=>'0'); next_pc<=(others=>'0'); instruction<=(others=>'0');
                operand_a<=(others=>'0'); operand_b<=(others=>'0'); value<=(others=>'0');
                halted<='0'; cycles<=(others=>'0'); retired<=(others=>'0');
            elsif halted='0' then
                cycles<=cycles+1; fsm_state<=next_fsm; micro_pc<=next_micro;
                if control(FETCH)='1' then instruction<=imem_rdata; end if;
                if control(DECODE)='1' then
                    operand_a<=regs(to_integer(unsigned(instruction(19 downto 15))));
                    operand_b<=regs(to_integer(unsigned(instruction(24 downto 20))));
                    next_pc<=pc+4;
                end if;
                if control(EXECUTE)='1' then
                    ri:=sign_extend(instruction(31 downto 20));
                    case op is
                        when OP_LUI => value<=shift_left(resize(unsigned(instruction(31 downto 12)),32),12);
                        when OP_IMM | OP_REG =>
                            if op=OP_IMM then rs:=ri; else rs:=operand_b; end if;
                            shift_amount:=to_integer(rs(4 downto 0));
                            case fn is
                                when "001" => value<=shift_left(operand_a,shift_amount);
                                when "010" =>
                                    if signed(operand_a)<signed(rs) then value<=to_unsigned(1,32);
                                    else value<=(others=>'0'); end if;
                                when "100" => value<=operand_a xor rs;
                                when "101" => value<=shift_right(operand_a,shift_amount);
                                when "110" => value<=operand_a or rs;
                                when "111" => value<=operand_a and rs;
                                when others =>
                                    if op=OP_REG and instruction(30)='1' then value<=operand_a-rs;
                                    else value<=operand_a+rs; end if;
                            end case;
                        when OP_LOAD => value<=operand_a+ri;
                        when OP_STORE =>
                            value<=operand_a+sign_extend(instruction(31 downto 25) & instruction(11 downto 7));
                        when OP_BRANCH =>
                            if (fn="000" and operand_a=operand_b) or (fn="001" and operand_a/=operand_b) or
                               (fn="100" and signed(operand_a)<signed(operand_b)) then
                                next_pc<=pc+sign_extend(instruction(31) & instruction(7) &
                                    instruction(30 downto 25) & instruction(11 downto 8) & '0');
                            end if;
                        when OP_JAL =>
                            value<=pc+4;
                            next_pc<=pc+sign_extend(instruction(31) & instruction(19 downto 12) &
                                instruction(20) & instruction(30 downto 21) & '0');
                        when OP_JALR => value<=pc+4; next_pc<=(operand_a+ri) and x"fffffffe";
                        when others => null;
                    end case;
                end if;
                if control(MEMORY)='1' then value<=unsigned(dmem_rdata); end if;
                if control(FINISH)='1' then
                    retired<=retired+1; pc<=next_pc;
                    if instruction=INSN_EBREAK then halted<='1'; end if;
                    destination:=to_integer(unsigned(instruction(11 downto 7)));
                    if destination/=0 and (op=OP_LUI or op=OP_REG or op=OP_IMM or
                       op=OP_LOAD or op=OP_JAL or op=OP_JALR) then regs(destination)<=value; end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
