library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rvc_compressed_decoder is
    port(window: in std_logic_vector(31 downto 0); instruction: out std_logic_vector(31 downto 0);
         length_bytes: out unsigned(2 downto 0); illegal: out std_logic);
end entity;
architecture rtl of rvc_compressed_decoder is
begin
    process(all)
        variable c: std_logic_vector(15 downto 0);
        variable rd,rs1,rs2: std_logic_vector(4 downto 0);
        variable imm_i: std_logic_vector(11 downto 0);
        variable imm_b: std_logic_vector(12 downto 0);
        variable imm_j: std_logic_vector(20 downto 0);
        variable result: std_logic_vector(31 downto 0);
        variable len: unsigned(2 downto 0);
        variable bad: std_logic;
    begin
        c:=window(15 downto 0); result:=(others=>'0'); len:=to_unsigned(2,3); bad:='0';
        rd:=(others=>'0'); rs1:=(others=>'0'); rs2:=(others=>'0');
        imm_i:=(others=>'0'); imm_b:=(others=>'0'); imm_j:=(others=>'0');
        if c(1 downto 0)="11" then result:=window; len:=to_unsigned(4,3);
        elsif c(1 downto 0)="00" and (c(15 downto 13)="010" or c(15 downto 13)="110") then
            rs1:="01" & c(9 downto 7); rd:="01" & c(4 downto 2);
            imm_i:="00000" & c(5) & c(12 downto 10) & c(6) & "00";
            if c(15 downto 13)="010" then result:=imm_i & rs1 & "010" & rd & "0000011";
            else result:=imm_i(11 downto 5) & rd & rs1 & "010" & imm_i(4 downto 0) & "0100011"; end if;
        elsif c(1 downto 0)="01" and c(15 downto 13)="000" then
            rd:=c(11 downto 7); imm_i:=(others=>c(12)); imm_i(4 downto 0):=c(6 downto 2);
            result:=imm_i & rd & "000" & rd & "0010011";
        elsif c(1 downto 0)="01" and c(15 downto 13)="110" then
            rs1:="01" & c(9 downto 7); imm_b:=(others=>c(12));
            imm_b(8 downto 0):=c(12) & c(6 downto 5) & c(2) & c(11 downto 10) & c(4 downto 3) & '0';
            result:=imm_b(12) & imm_b(10 downto 5) & "00000" & rs1 & "000" & imm_b(4 downto 1) & imm_b(11) & "1100011";
        elsif c(1 downto 0)="01" and (c(15 downto 13)="101" or c(15 downto 13)="001") then
            if c(15 downto 13)="001" then rd:="00001"; else rd:="00000"; end if;
            imm_j:=(others=>c(12));
            imm_j(11 downto 0):=c(12) & c(8) & c(10 downto 9) & c(6) & c(7) & c(2) & c(11) & c(5 downto 3) & '0';
            result:=imm_j(20) & imm_j(10 downto 1) & imm_j(11) & imm_j(19 downto 12) & rd & "1101111";
        elsif c(1 downto 0)="10" and c(15 downto 13)="100" and c(6 downto 2)/="00000" then
            rd:=c(11 downto 7); rs2:=c(6 downto 2);
            if c(12)='1' then rs1:=rd; else rs1:="00000"; end if;
            result:="0000000" & rs2 & rs1 & "000" & rd & "0110011";
        else bad:='1'; end if;
        instruction<=result; length_bytes<=len; illegal<=bad;
    end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity rvc_fetch is
    port(pc: in unsigned(31 downto 0); window: in std_logic_vector(31 downto 0);
         instruction: out std_logic_vector(31 downto 0); next_pc: out unsigned(31 downto 0);
         length_bytes: out unsigned(2 downto 0); illegal: out std_logic);
end entity;
architecture rtl of rvc_fetch is
    signal len: unsigned(2 downto 0);
begin
    decoder: entity work.rvc_compressed_decoder port map(window,instruction,len,illegal);
    length_bytes<=len; next_pc<=pc+resize(len,32);
end architecture;
