library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

entity tb_multicycle_microcode_baseline is end entity;
architecture test of tb_multicycle_microcode_baseline is
    subtype word is std_logic_vector(31 downto 0);
    type words is array(0 to 2) of word;
    type counts is array(0 to 2) of unsigned(31 downto 0);
    type datamemory is array(0 to 63) of word;
    type memories is array(0 to 2) of datamemory;
    type instructions is array(0 to 24) of word;
    type naturals is array(0 to 2) of natural;
    impure function load_image return instructions is
        file source : text open read_mode is "../../../../appC_pipelining/multicycle_microcode_baseline/program.hex";
        variable row : line;
        variable image : instructions;
    begin
        for i in image'range loop readline(source,row); hread(row,image(i)); end loop;
        return image;
    end;
    constant rom : instructions := load_image;
    signal memory : memories;
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal dbg_raddr : std_logic_vector(4 downto 0) := (others=>'0');
    signal ia, inst, da, wd, data_word, dbg : words;
    signal cycles, retired : counts;
    signal stores : naturals;
    signal halted, we : std_logic_vector(2 downto 0);
begin
    clk<=not clk after 5 ns;
    cpu: for i in 0 to 2 generate
        inst(i)<=rom(to_integer(unsigned(ia(i)(6 downto 2)))) when
            not is_x(ia(i)) and unsigned(ia(i))<100 else (others=>'0');
        data_word(i)<=memory(i)(to_integer(unsigned(da(i)(7 downto 2)))) when
            not is_x(da(i)) else (others=>'0');
        multi: if i<2 generate
            core: entity work.multicycle_microcode_baseline generic map(MICROCODE=>i=1)
                port map(clk,rst_n,ia(i),inst(i),da(i),wd(i),we(i),data_word(i),dbg_raddr,dbg(i),
                         halted(i),cycles(i),retired(i));
        end generate;
        pipelined: if i=2 generate
            core: entity work.rv32i_pipeline
                port map(clk,rst_n,ia(i),inst(i),da(i),wd(i),we(i),data_word(i),dbg_raddr,dbg(i),
                         halted(i),cycles(i),retired(i),open,open);
        end generate;
        process(clk)
        begin
            if rising_edge(clk) then
                if rst_n='0' then stores(i)<=0; memory(i)<=(others=>(others=>'0'));
                elsif we(i)='1' then
                    memory(i)(to_integer(unsigned(da(i)(7 downto 2))))<=wd(i);
                    stores(i)<=stores(i)+1;
                end if;
            end if;
        end process;
    end generate;
    process
        variable count : natural := 0;
    begin
        wait until falling_edge(clk); wait until falling_edge(clk); rst_n<='1';
        while halted/="111" and count<250 loop
            wait until falling_edge(clk); count:=count+1;
            assert cycles(0)=cycles(1) and retired(0)=retired(1) and ia(0)=ia(1) and we(0)=we(1) and
                   (we(0)='0' or (da(0)=da(1) and wd(0)=wd(1)))
                report "hardwired and microcode cycle mismatch" severity failure;
        end loop;
        assert halted="111" and cycles(0)=197 and cycles(2)=78 and 2*cycles(0)>=5*cycles(2)
            report "elapsed cycles" severity failure;
        for i in 0 to 2 loop
            assert retired(i)=49 and stores(i)=2 and unsigned(memory(i)(0))=12 and unsigned(memory(i)(1))=55
                report "retirement or memory state" severity failure;
        end loop;
        assert memory(0)=memory(2) and memory(1)=memory(2) report "memory parity" severity failure;
        for i in 0 to 31 loop
            dbg_raddr<=std_logic_vector(to_unsigned(i,5)); wait for 1 ns;
            assert dbg(0)=dbg(2) and dbg(1)=dbg(2) report "register parity" severity failure;
        end loop;
        report "197 vs 78 cycles, 49 instructions per core";
        report "TEST PASSED"; finish;
    end process;
end architecture;
