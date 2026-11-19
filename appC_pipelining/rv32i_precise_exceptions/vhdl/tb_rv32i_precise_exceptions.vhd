library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_rv32i_precise_exceptions is end entity;
architecture test of tb_rv32i_precise_exceptions is
    subtype word is std_logic_vector(31 downto 0);
    type words is array(0 to 1) of word;
    signal clk : std_logic := '0';
    signal rst_n, irq : std_logic := '0';
    signal imem_rdata, imem_addr, dmem_addr, dmem_wdata, store_addr, mepc, mcause, dbg_rdata : word;
    signal dmem_rdata : word;
    signal dmem_we, halted, trap, fault_overlap, imem_fault, dmem_fault : std_logic;
    signal cycles, retired : unsigned(31 downto 0);
    signal dbg_raddr : std_logic_vector(4 downto 0) := (others=>'0');
    signal memory : words;
    signal test_mode : natural := 0;
begin
    clk<=not clk after 5 ns;
    imem_fault<='1' when test_mode=2 and imem_addr=x"00000004" else '0';
    dmem_fault<='1' when test_mode=0 and dmem_addr=x"00000004" else '0';
    dmem_rdata<=memory(to_integer(unsigned(dmem_addr(2 downto 2)))) when not is_x(dmem_addr) else (others=>'0');
    dut: entity work.rv32i_precise_exceptions
        port map(clk=>clk,rst_n=>rst_n,imem_fault=>imem_fault,dmem_fault=>dmem_fault,irq=>irq,
                  store_addr=>store_addr,mepc=>mepc,mcause=>mcause,trap=>trap,fault_overlap=>fault_overlap,
                  imem_addr=>imem_addr,imem_rdata=>imem_rdata,dmem_addr=>dmem_addr,dmem_wdata=>dmem_wdata,
                  dmem_we=>dmem_we,dmem_rdata=>dmem_rdata,dbg_raddr=>dbg_raddr,dbg_rdata=>dbg_rdata,
                  halted=>halted,stat_cycles=>cycles,stat_retired=>retired,stat_load_stalls=>open,stat_flushes=>open);
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n='0' then memory<=(others=>(others=>'0'));
            elsif dmem_we='1' then memory(to_integer(unsigned(store_addr(2 downto 2))))<=dmem_wdata; end if;
        end if;
    end process;
    process(all)
    begin
        imem_rdata<=x"00000013";
        case imem_addr is
            when x"00000000" => imem_rdata<=x"00700093";
            when x"00000004" =>
                if test_mode=1 then imem_rdata<=x"ffffffff";
                elsif test_mode=4 then imem_rdata<=x"00000073"; else imem_rdata<=x"00102023"; end if;
            when x"00000008" => if test_mode=0 then imem_rdata<=x"00102223"; end if;
            when x"0000000c" => if test_mode=0 then imem_rdata<=x"00000073"; end if;
            when x"00000010" => imem_rdata<=x"00900193";
            when x"00000014" => imem_rdata<=x"00100073";
            when x"00000080" => imem_rdata<=x"01000113";
            when x"00000084" => imem_rdata<=x"34111273";
            when x"00000088" => imem_rdata<=x"342012f3";
            when x"0000008c" => imem_rdata<=x"30200073";
            when x"00000090" => imem_rdata<=x"06300313";
            when others => null;
        end case;
    end process;
    process
        procedure tick is
        begin wait until rising_edge(clk); wait for 1 ns; end;
        procedure check_reg(reg_id : natural; expected : word) is
        begin
            dbg_raddr<=std_logic_vector(to_unsigned(reg_id,5)); wait for 1 ns;
            assert dbg_rdata=expected report "wrong register x" & integer'image(reg_id) severity failure;
        end;
        variable count : natural;
        variable saw_overlap : boolean;
        variable expected_pc, expected_cause : word;
    begin
        for n in 0 to 4 loop
            test_mode<=n; rst_n<='0'; irq<='0'; tick; rst_n<='1';
            expected_pc:=x"00000004";
            case n is
                when 0 => expected_pc:=x"00000008"; expected_cause:=x"00000007";
                when 1 => expected_cause:=x"00000002";
                when 2 => expected_cause:=x"00000001";
                when 3 => expected_cause:=x"8000000b";
                when others => expected_cause:=x"0000000b";
            end case;
            if n=3 then tick; irq<='1'; tick; irq<='0'; end if;
            count:=0; saw_overlap:=false;
            while trap/='1' and count<20 loop
                if fault_overlap='1' then saw_overlap:=true; end if;
                tick; count:=count+1;
            end loop;
            assert trap='1' and mepc=expected_pc and mcause=expected_cause and imem_addr=x"00000080"
                report "trap mismatch mode " & integer'image(n) severity failure;
            if n=0 then
                assert saw_overlap and memory(0)=x"00000007" and memory(1)=x"00000000" and retired=2
                    report "two faults did not preserve older effects" severity failure;
            else
                assert memory(0)=x"00000000" and memory(1)=x"00000000" and retired=1
                    report "faulted or younger store committed" severity failure;
            end if;
            check_reg(1,x"00000007"); check_reg(3,x"00000000");
            count:=0;
            while halted/='1' and count<80 loop
                tick; count:=count+1;
                assert trap='0' report "unexpected second trap" severity failure;
            end loop;
            assert halted='1' and memory(1)=x"00000000" report "resume did not halt cleanly" severity failure;
            check_reg(3,x"00000009"); check_reg(4,expected_pc); check_reg(5,expected_cause);
            check_reg(6,x"00000000");
        end loop;
        report "TEST PASSED"; finish;
    end process;
end architecture;
