library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_r4000_superpipeline8 is end entity;
architecture test of tb_r4000_superpipeline8 is
    subtype word is std_logic_vector(63 downto 0);
    type words is array(0 to 2) of word;
    type addresses is array(0 to 2) of std_logic_vector(31 downto 0);
    type counts is array(0 to 2) of unsigned(31 downto 0);
    type bank is array(0 to 1) of word;
    type banks is array(0 to 2) of bank;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal slot_dependency : boolean := false;
    signal dbg_raddr : std_logic_vector(4 downto 0) := (others=>'0');
    signal halted, we : std_logic_vector(2 downto 0);
    signal ia, inst : addresses;
    signal da, wd, dbg, read_word : words;
    signal cycles, retired, load_stalls, flushes : counts;
    signal mem : banks;
    function program_word(a : std_logic_vector(31 downto 0); dependent : boolean) return std_logic_vector is
    begin
        if dependent then
            case a is
                when x"00000000" => return x"dc010000";
                when x"00000004" => return x"10000002";
                when x"00000008" => return x"0021182d";
                when x"0000000c" => return x"64040063";
                when x"00000010" => return x"0000000d";
                when others => return x"00000000";
            end case;
        end if;
        case a is
            when x"00000000" => return x"dc010000";
            when x"00000004" => return x"0021102d";
            when x"00000008" => return x"10000002";
            when x"0000000c" => return x"64030001";
            when x"00000010" => return x"64040063";
            when x"00000014" => return x"fc020008";
            when x"00000018" => return x"0000000d";
            when others => return x"00000000";
        end case;
    end;
begin
    clk<=not clk after 5 ns;
    cpu: for i in 0 to 2 generate
        inst(i)<=program_word(ia(i),slot_dependency);
        read_word(i)<=mem(i)(1) when da(i)(3)='1' else mem(i)(0);
        baseline: if i=0 generate
            core: entity work.mips_pipeline generic map(XLEN=>64)
                port map(clk,rst_n,ia(i),inst(i),da(i),wd(i),we(i),read_word(i),dbg_raddr,dbg(i),
                         halted(i),cycles(i),retired(i),load_stalls(i),open,flushes(i));
        end generate;
        eight_stage: if i/=0 generate
            core: entity work.r4000_superpipeline8 generic map(XLEN=>64,DELAY_SLOT=>i=2)
                port map(clk,rst_n,ia(i),inst(i),da(i),wd(i),we(i),read_word(i),dbg_raddr,dbg(i),
                         halted(i),cycles(i),retired(i),load_stalls(i),open,flushes(i));
        end generate;
        process(clk)
        begin
            if rising_edge(clk) then
                if rst_n='0' then mem(i)(0)<=x"0000000100000003"; mem(i)(1)<=(others=>'0');
                elsif we(i)='1' then
                    if da(i)(3)='1' then mem(i)(1)<=wd(i); else mem(i)(0)<=wd(i); end if;
                end if;
            end if;
        end process;
    end generate;
    process
        variable count : natural := 0;
    begin
        wait until falling_edge(clk); wait until falling_edge(clk); rst_n<='1';
        while halted/="111" and count<70 loop
            wait until falling_edge(clk); count:=count+1;
        end loop;
        assert halted="111" and cycles(0)=11 and cycles(1)=17 and cycles(2)=17 and
               retired(0)=5 and retired(1)=5 and retired(2)=6 report "timing/counter mismatch" severity failure;
        assert load_stalls(0)=1 and load_stalls(1)=2 and load_stalls(2)=2 and
               flushes(0)=1 and flushes(1)=3 and flushes(2)=2 report "hazard penalty mismatch" severity failure;
        for i in 0 to 2 loop
            assert mem(i)(0)=x"0000000100000003" and mem(i)(1)=x"0000000200000006"
                report "memory mismatch" severity failure;
        end loop;
        for r in 0 to 31 loop
            dbg_raddr<=std_logic_vector(to_unsigned(r,5)); wait for 1 ns;
            assert dbg(0)=dbg(1) and ((r/=3 and dbg(2)=dbg(0)) or (r=3 and unsigned(dbg(2))=1))
                report "register parity at x" & integer'image(r) severity failure;
        end loop;
        wait until falling_edge(clk); rst_n<='0'; slot_dependency<=true;
        wait until falling_edge(clk); rst_n<='1'; count:=0;
        while halted/="111" and count<70 loop
            wait until falling_edge(clk); count:=count+1;
        end loop;
        dbg_raddr<="00011"; wait for 1 ns;
        assert halted="111" and unsigned(dbg(0))=0 and unsigned(dbg(1))=0 and dbg(2)=x"0000000200000006" and
               load_stalls(1)=0 and load_stalls(2)=1 and retired(2)=4
            report "redirect lost a stalled delay-slot instruction" severity failure;
        report "TEST PASSED"; finish;
    end process;
end architecture;
