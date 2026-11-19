library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

entity tb_rvc_compressed_decoder is end entity;
architecture test of tb_rvc_compressed_decoder is
    signal pc: unsigned(31 downto 0) := (others=>'0');
    signal window: std_logic_vector(31 downto 0) := (others=>'0');
    signal instruction: std_logic_vector(31 downto 0);
    signal next_pc: unsigned(31 downto 0);
    signal length_bytes: unsigned(2 downto 0);
    signal illegal: std_logic;
begin
    dut: entity work.rvc_fetch port map(pc,window,instruction,next_pc,length_bytes,illegal);
    process
        type halfwords is array(0 to 9) of std_logic_vector(15 downto 0);
        type registers is array(0 to 31) of integer;
        constant mem: halfwords := (x"0413",x"0030",x"147d",x"8493",x"0014",x"c011",x"bfe5",x"8513",x"0004",x"0000");
        variable regs: registers := (others=>0);
        file vectors: text;
        variable status: file_open_status;
        variable row: line;
        variable expected_c: std_logic_vector(15 downto 0);
        variable expected_word: std_logic_vector(31 downto 0);
        variable expected_illegal,pc_v,steps,bytes,rd,rs1,immediate: integer;
        variable bimm: std_logic_vector(12 downto 0);
        variable jimm: std_logic_vector(20 downto 0);
    begin
        file_open(status,vectors,"../../../../appA_isa/rvc_compressed_decoder/golden.txt",read_mode);
        assert status=open_ok report "TEST FAILED: missing golden vectors" severity failure;
        pc<=to_unsigned(100,32);
        for c in 0 to 65535 loop
            if c mod 4/=3 then
                assert not endfile(vectors) report "TEST FAILED: truncated vectors" severity failure;
                readline(vectors,row); hread(row,expected_c); hread(row,expected_word); read(row,expected_illegal);
                assert unsigned(expected_c)=to_unsigned(c,16) report "TEST FAILED: vector order" severity failure;
                window<=x"fa05" & std_logic_vector(to_unsigned(c,16)); wait for 1 ns;
                assert length_bytes=2 and next_pc=102 and instruction=expected_word and
                       ((expected_illegal=0 and illegal='0') or (expected_illegal=1 and illegal='1'))
                    report "TEST FAILED: compressed expansion" severity failure;
            end if;
        end loop;
        file_close(vectors);
        window<=x"123456f3"; wait for 1 ns;
        assert illegal='0' and length_bytes=4 and instruction=x"123456f3" and next_pc=104
            report "TEST FAILED: passthrough" severity failure;
        pc_v:=0; steps:=0; bytes:=0;
        while pc_v<18 and steps<50 loop
            pc<=to_unsigned(pc_v,32); window<=mem(pc_v/2+1) & mem(pc_v/2); wait for 1 ns;
            assert illegal='0' report "TEST FAILED: loop decode" severity failure;
            steps:=steps+1; bytes:=bytes+to_integer(length_bytes);
            rd:=to_integer(unsigned(instruction(11 downto 7))); rs1:=to_integer(unsigned(instruction(19 downto 15)));
            case instruction(6 downto 0) is
                when "0010011" =>
                    immediate:=to_integer(signed(instruction(31 downto 20)));
                    if rd/=0 then regs(rd):=regs(rs1)+immediate; end if;
                    pc_v:=to_integer(next_pc);
                when "1100011" =>
                    bimm:=instruction(31) & instruction(7) & instruction(30 downto 25) & instruction(11 downto 8) & '0';
                    immediate:=to_integer(signed(bimm));
                    if regs(rs1)=0 then pc_v:=pc_v+immediate; else pc_v:=to_integer(next_pc); end if;
                when "1101111" =>
                    jimm:=instruction(31) & instruction(19 downto 12) & instruction(20) & instruction(30 downto 21) & '0';
                    immediate:=to_integer(signed(jimm));
                    if rd/=0 then regs(rd):=to_integer(next_pc); end if;
                    pc_v:=pc_v+immediate;
                when others => assert false report "TEST FAILED: loop opcode" severity failure;
            end case;
        end loop;
        assert pc_v=18 and regs(8)=0 and regs(9)=3 and regs(10)=3 and steps=13 and bytes=36
            report "TEST FAILED: loop result" severity failure;
        report "TEST PASSED"; finish;
    end process;
end architecture;
