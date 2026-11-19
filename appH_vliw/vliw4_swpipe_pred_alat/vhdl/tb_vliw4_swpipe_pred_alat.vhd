library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

entity tb_vliw4_swpipe_pred_alat is end entity;
architecture test of tb_vliw4_swpipe_pred_alat is
    subtype word is std_logic_vector(31 downto 0);
    subtype bundle_word is std_logic_vector(127 downto 0);
    type program is array(0 to 95) of bundle_word;
    type ram is array(0 to 63) of word;
    impure function load_programs return program is
        file source : text open read_mode is "../../../../appH_vliw/vliw4_swpipe_pred_alat/programs.hex";
        variable row : line;
        variable image : program;
    begin
        for i in image'range loop readline(source,row); hread(row,image(i)); end loop;
        return image;
    end;
    constant ROM : program := load_programs;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal dbg_raddr : std_logic_vector(3 downto 0) := (others=>'0');
    signal memory,base_memory : ram;
    signal imem_addr,dmem_addr,dmem_wdata,dbg_rdata,dmem_rdata : word;
    signal base_pc,base_addr,base_value,base_data : word;
    signal imem_rdata,base_instruction : bundle_word;
    signal dbg_nat,halted,dmem_we,dmem_fault,base_we,base_halted : std_logic;
    signal trap_cause : unsigned(2 downto 0);
    signal bundles,ops,alat_failures,base_bundles,base_ops : unsigned(31 downto 0);
    signal program_id : natural := 1;
begin
    clk<=not clk after 5 ns;
    imem_rdata<=ROM(16*program_id+to_integer(unsigned(imem_addr(3 downto 0)))) when not is_x(imem_addr) else (others=>'0');
    dmem_rdata<=memory(to_integer(unsigned(dmem_addr(7 downto 2)))) when not is_x(dmem_addr) else (others=>'0');
    dmem_fault<='1' when not is_x(dmem_addr) and unsigned(dmem_addr)>=256 else '0';
    base_instruction<=ROM(to_integer(unsigned(base_pc(3 downto 0)))) when not is_x(base_pc) else (others=>'0');
    base_data<=base_memory(to_integer(unsigned(base_addr(7 downto 2)))) when not is_x(base_addr) else (others=>'0');
    dut: entity work.vliw4_swpipe_pred_alat
        port map(clk,rst_n,imem_addr,imem_rdata,dmem_addr,dmem_wdata,dmem_we,dmem_rdata,dmem_fault,
                 dbg_raddr,dbg_rdata,dbg_nat,halted,trap_cause,bundles,ops,alat_failures);
    baseline: entity work.vliw4
        port map(clk,rst_n,base_pc,base_instruction,base_addr,base_value,base_we,base_data,
                 dbg_raddr,open,base_halted,base_bundles,base_ops);
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n='0' then
                memory<=(others=>(others=>'0')); base_memory<=(others=>(others=>'0'));
                for i in 0 to 7 loop
                    memory(i)<=std_logic_vector(to_unsigned(i+1,32)); base_memory(i)<=std_logic_vector(to_unsigned(i+1,32));
                    memory(16+i)<=std_logic_vector(to_unsigned(100*i,32));
                    base_memory(16+i)<=std_logic_vector(to_unsigned(100*i,32));
                end loop;
            else
                if dmem_we='1' then memory(to_integer(unsigned(dmem_addr(7 downto 2))))<=dmem_wdata; end if;
                if base_we='1' then base_memory(to_integer(unsigned(base_addr(7 downto 2))))<=base_value; end if;
            end if;
        end if;
    end process;
    process
        procedure tick is
        begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure run_case(id : natural) is
            variable elapsed : natural := 0;
        begin
            program_id<=id; rst_n<='0'; tick; rst_n<='1';
            while (halted/='1' or base_halted/='1') and elapsed<80 loop tick; elapsed:=elapsed+1; end loop;
            assert halted='1' and base_halted='1' report "timeout" severity failure;
        end;
    begin
        run_case(1);
        assert base_bundles=31 and base_ops=60 and bundles=29 and ops*base_bundles>base_ops*bundles and trap_cause=0
            report "kernel schedule/IPC" severity failure;
        for i in 0 to 7 loop
            assert unsigned(memory(16+i))=103*i+3 and base_memory(16+i)=memory(16+i)
                report "DAXPY result" severity failure;
        end loop;
        report "DAXPY ops/bundles: " & integer'image(to_integer(ops)) & "/" & integer'image(to_integer(bundles)) &
               " versus " & integer'image(to_integer(base_ops)) & "/" & integer'image(to_integer(base_bundles));
        run_case(2);
        assert unsigned(memory(16))=3 and unsigned(memory(17))=100 and trap_cause=0
            report "short prologue/epilogue" severity failure;
        run_case(3); dbg_raddr<=x"4"; wait for 1 ns;
        assert trap_cause=0 and dbg_nat='1' and unsigned(memory(25))=0
            report "suppressed load/check/store" severity failure;
        run_case(4); dbg_raddr<=x"2"; wait for 1 ns;
        assert trap_cause=2 and unsigned(dbg_rdata)=0 and unsigned(memory(25))=0
            report "NaT must trap before same-bundle side effects" severity failure;
        run_case(5); dbg_raddr<=x"2"; wait for 1 ns;
        assert trap_cause=0 and alat_failures=2 and unsigned(dbg_rdata)=99 and
               unsigned(memory(0))=42 and unsigned(memory(5))=42 report "ALAT overlap/replacement" severity failure;
        report "TEST PASSED"; finish;
    end process;
end architecture;
