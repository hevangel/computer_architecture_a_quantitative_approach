library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vliw4_swpipe_pred_alat is
    port (
        clk,rst_n : in std_logic;
        imem_addr : out std_logic_vector(31 downto 0);
        imem_rdata : in std_logic_vector(127 downto 0);
        dmem_addr,dmem_wdata : out std_logic_vector(31 downto 0);
        dmem_we : out std_logic;
        dmem_rdata : in std_logic_vector(31 downto 0);
        dmem_fault : in std_logic;
        dbg_raddr : in std_logic_vector(3 downto 0);
        dbg_rdata : out std_logic_vector(31 downto 0);
        dbg_nat,halted : out std_logic;
        trap_cause : out unsigned(2 downto 0);
        bundles,ops,alat_failures : out unsigned(31 downto 0)
    );
end entity;
architecture rtl of vliw4_swpipe_pred_alat is
    subtype word is unsigned(31 downto 0);
    type reg_file is array(0 to 15) of word;
    type indices is array(0 to 3) of natural range 0 to 15;
    type immediates is array(0 to 3) of word;
    type alu_words is array(0 to 1) of word;
    type decoded is record
        opc,rd,ra,rb,raw_rd : indices;
        imm : immediates;
        alu : alu_words;
        alu_write,alu_nat,predicate_write,predicate_value : std_logic_vector(1 downto 0);
        issue_load,issue_store,rotate_now,stop_now,check_failed : boolean;
        address,next_pc : word;
        trap : natural range 0 to 2;
        op_count : natural range 0 to 4;
    end record;
    constant ADD_OP:natural:=1; constant SUB_OP:natural:=2; constant MUL_OP:natural:=3;
    constant ADDI:natural:=4; constant LD:natural:=5; constant ST:natural:=6; constant BNEZ:natural:=7;
    constant JMP:natural:=8; constant LDS:natural:=9; constant LDA:natural:=10; constant CHKS:natural:=11;
    constant CHKA:natural:=12; constant PSET:natural:=13; constant ROTBR:natural:=14; constant HALT_OP:natural:=15;
    signal regs : reg_file := (others=>(others=>'0'));
    signal nat_bits : std_logic_vector(15 downto 0) := (others=>'0');
    signal predicates : std_logic_vector(7 downto 0) := x"01";
    signal pc : word := (others=>'0');
    signal rotated : boolean := false;
    signal alat_valid : std_logic_vector(3 downto 0) := (others=>'0');
    signal alat_rd : indices := (others=>0);
    signal alat_addr : immediates := (others=>(others=>'0'));
    signal alat_next : natural range 0 to 3 := 0;
    signal load_pending : boolean := false;
    signal load_nat : std_logic := '0';
    signal load_rd : natural range 0 to 15 := 0;
    signal load_value : word := (others=>'0');
    signal action : decoded;

    function physical(reg_id : natural; bank : boolean) return natural is
    begin
        if bank and reg_id>=8 then return 8+(reg_id-8+4) mod 8; end if;
        return reg_id;
    end;
    function overlaps(a,b : word) return boolean is
    begin return resize(a,33)<resize(b,33)+4 and resize(b,33)<resize(a,33)+4; end;
begin
    imem_addr<=std_logic_vector(pc);
    dbg_rdata<=std_logic_vector(regs(physical(to_integer(unsigned(dbg_raddr)),rotated)));
    dbg_nat<=nat_bits(physical(to_integer(unsigned(dbg_raddr)),rotated));
    dmem_addr<=std_logic_vector(action.address);
    dmem_wdata<=std_logic_vector(regs(action.rb(2)));
    dmem_we<='1' when rst_n='1' and halted='0' and action.issue_store and action.trap=0 else '0';

    process(all)
        variable v : decoded;
        variable op_word : std_logic_vector(31 downto 0);
        variable guard_on : std_logic;
        variable found : boolean;
    begin
        v.op_count:=0; v.alu_write:="00"; v.alu_nat:="00";
        v.predicate_write:="00"; v.predicate_value:="00";
        v.issue_load:=false; v.issue_store:=false; v.rotate_now:=false; v.stop_now:=false;
        v.check_failed:=false; v.trap:=0; v.next_pc:=pc+1;
        for i in 0 to 3 loop
            op_word:=imem_rdata(32*i+31 downto 32*i);
            if is_x(op_word) then op_word:=(others=>'0'); end if;
            guard_on:=predicates(to_integer(unsigned(op_word(15 downto 13)))) xor op_word(12);
            if guard_on='1' then v.opc(i):=to_integer(unsigned(op_word(31 downto 28))); else v.opc(i):=0; end if;
            v.raw_rd(i):=to_integer(unsigned(op_word(27 downto 24)));
            v.rd(i):=physical(v.raw_rd(i),rotated);
            v.ra(i):=physical(to_integer(unsigned(op_word(23 downto 20))),rotated);
            v.rb(i):=physical(to_integer(unsigned(op_word(19 downto 16))),rotated);
            v.imm(i):=unsigned(resize(signed(op_word(11 downto 0)),32));
        end loop;
        for i in 0 to 1 loop
            v.alu(i):=(others=>'0');
            case v.opc(i) is
                when ADD_OP => v.alu(i):=regs(v.ra(i))+regs(v.rb(i)); v.alu_write(i):='1';
                when SUB_OP => v.alu(i):=regs(v.ra(i))-regs(v.rb(i)); v.alu_write(i):='1';
                when MUL_OP => v.alu(i):=resize(regs(v.ra(i))*regs(v.rb(i)),32); v.alu_write(i):='1';
                when ADDI => v.alu(i):=regs(v.ra(i))+v.imm(i); v.alu_write(i):='1';
                when PSET =>
                    v.predicate_write(i):='1';
                    if regs(v.ra(i))=regs(v.rb(i)) then v.predicate_value(i):=not v.imm(i)(0);
                    else v.predicate_value(i):=v.imm(i)(0); end if;
                    if nat_bits(v.ra(i))='1' or nat_bits(v.rb(i))='1' then v.trap:=2; end if;
                when others => null;
            end case;
            if v.alu_write(i)='1' then
                v.alu_nat(i):=nat_bits(v.ra(i));
                if v.opc(i)/=ADDI then v.alu_nat(i):=v.alu_nat(i) or nat_bits(v.rb(i)); end if;
            end if;
            if v.alu_write(i)='1' or v.predicate_write(i)='1' then v.op_count:=v.op_count+1; end if;
        end loop;
        v.address:=regs(v.ra(2))+v.imm(2);
        v.issue_load:=v.opc(2)=LD or v.opc(2)=LDS or v.opc(2)=LDA;
        v.issue_store:=v.opc(2)=ST;
        if v.issue_load or v.issue_store then v.op_count:=v.op_count+1; end if;
        if (v.issue_load and v.opc(2)/=LDS and (dmem_fault='1' or nat_bits(v.ra(2))='1')) or
           (v.issue_store and (dmem_fault='1' or nat_bits(v.ra(2))='1' or nat_bits(v.rb(2))='1')) then
            v.trap:=1;
        end if;
        case v.opc(3) is
            when BNEZ | ROTBR =>
                if nat_bits(v.ra(3))='1' then v.trap:=2;
                elsif regs(v.ra(3))/=0 then v.next_pc:=v.imm(3); end if;
                v.rotate_now:=v.opc(3)=ROTBR;
                v.op_count:=v.op_count+1;
            when JMP => v.next_pc:=v.imm(3); v.op_count:=v.op_count+1;
            when CHKS =>
                if nat_bits(v.ra(3))='1' then v.trap:=2; end if;
                v.op_count:=v.op_count+1;
            when CHKA =>
                found:=false;
                for i in 0 to 3 loop
                    if alat_valid(i)='1' and alat_rd(i)=v.ra(3) and
                       not (v.issue_store and overlaps(alat_addr(i),v.address)) then found:=true; end if;
                end loop;
                v.check_failed:=not found;
                if not found then v.next_pc:=v.imm(3); end if;
                v.op_count:=v.op_count+1;
            when HALT_OP => v.stop_now:=true; v.op_count:=v.op_count+1;
            when others => null;
        end case;
        action<=v;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n='0' then
                pc<=(others=>'0'); rotated<=false; predicates<=x"01"; nat_bits<=(others=>'0');
                halted<='0'; trap_cause<=(others=>'0'); load_pending<=false; load_nat<='0';
                load_rd<=0; load_value<=(others=>'0'); bundles<=(others=>'0'); ops<=(others=>'0');
                alat_failures<=(others=>'0'); alat_valid<=(others=>'0'); alat_next<=0;
                regs<=(others=>(others=>'0')); alat_rd<=(others=>0); alat_addr<=(others=>(others=>'0'));
            elsif halted='0' then
                if load_pending and load_rd/=0 then regs(load_rd)<=load_value; nat_bits(load_rd)<=load_nat; end if;
                load_pending<=false;
                bundles<=bundles+1;
                if action.trap/=0 then halted<='1'; trap_cause<=to_unsigned(action.trap,3);
                else
                    ops<=ops+action.op_count;
                    for i in 0 to 1 loop
                        if action.alu_write(i)='1' and action.rd(i)/=0 then
                            regs(action.rd(i))<=action.alu(i); nat_bits(action.rd(i))<=action.alu_nat(i);
                        end if;
                        if action.predicate_write(i)='1' and action.raw_rd(i) mod 8/=0 then
                            predicates(action.raw_rd(i) mod 8)<=action.predicate_value(i);
                        end if;
                    end loop;
                    for i in 0 to 3 loop
                        if (action.issue_store and overlaps(alat_addr(i),action.address)) or
                           (action.issue_load and action.rd(2)=alat_rd(i)) or
                           (action.alu_write(0)='1' and action.rd(0)=alat_rd(i)) or
                           (action.alu_write(1)='1' and action.rd(1)=alat_rd(i)) then alat_valid(i)<='0'; end if;
                    end loop;
                    if action.issue_load then
                        load_pending<=true; load_rd<=action.rd(2);
                        if dmem_fault='1' or nat_bits(action.ra(2))='1' then
                            load_value<=(others=>'0'); load_nat<='1';
                        else load_value<=unsigned(dmem_rdata); load_nat<='0'; end if;
                        if action.opc(2)=LDA and action.rd(2)/=0 then
                            alat_valid(alat_next)<='1'; alat_rd(alat_next)<=action.rd(2);
                            alat_addr(alat_next)<=action.address; alat_next<=(alat_next+1) mod 4;
                        end if;
                    end if;
                    if action.check_failed then alat_failures<=alat_failures+1; end if;
                    if action.rotate_now then rotated<=not rotated; end if;
                    if action.stop_now then halted<='1'; end if;
                    pc<=action.next_pc;
                end if;
            end if;
        end if;
    end process;
end architecture;
