library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity simd_pack_shuffle is
    port(words_in: in std_logic_vector(255 downto 0); bytes_in: in std_logic_vector(63 downto 0);
         halfwords_in: in std_logic_vector(127 downto 0); signed_extend: in std_logic;
         byte_select: in std_logic_vector(23 downto 0); half_select: in std_logic_vector(7 downto 0);
         tile_in: in std_logic_vector(511 downto 0);
         packed16: out std_logic_vector(127 downto 0); packed8: out std_logic_vector(63 downto 0);
         extended_bytes: out std_logic_vector(127 downto 0); extended_halfwords: out std_logic_vector(255 downto 0);
         shuffled_bytes, shuffled_halfwords: out std_logic_vector(63 downto 0);
         tile_transposed: out std_logic_vector(511 downto 0));
end entity;
architecture rtl of simd_pack_shuffle is
begin
    process(all)
        variable p16, xb: std_logic_vector(127 downto 0);
        variable p8, sb, sh: std_logic_vector(63 downto 0);
        variable xh: std_logic_vector(255 downto 0);
        variable transposed: std_logic_vector(511 downto 0);
        variable word_value: signed(31 downto 0);
        variable half_value: signed(15 downto 0);
        variable bidx: natural range 0 to 7;
        variable hidx: natural range 0 to 3;
    begin
        p16:=(others=>'0'); p8:=(others=>'0'); xb:=(others=>'0'); xh:=(others=>'0');
        sb:=(others=>'0'); sh:=(others=>'0'); transposed:=(others=>'0');
        for i in 0 to 7 loop
            word_value:=signed(words_in(i*32+31 downto i*32));
            if word_value > to_signed(32767,32) then half_value:=to_signed(32767,16);
            elsif word_value < to_signed(-32768,32) then half_value:=to_signed(-32768,16);
            else half_value:=word_value(15 downto 0); end if;
            p16(i*16+15 downto i*16):=std_logic_vector(half_value);
            if half_value > to_signed(127,16) then p8(i*8+7 downto i*8):=x"7f";
            elsif half_value < to_signed(-128,16) then p8(i*8+7 downto i*8):=x"80";
            else p8(i*8+7 downto i*8):=std_logic_vector(half_value(7 downto 0)); end if;
            xb(i*16+7 downto i*16):=bytes_in(i*8+7 downto i*8);
            xb(i*16+15 downto i*16+8):=(others=>signed_extend and bytes_in(i*8+7));
            xh(i*32+15 downto i*32):=halfwords_in(i*16+15 downto i*16);
            xh(i*32+31 downto i*32+16):=(others=>signed_extend and halfwords_in(i*16+15));
            bidx:=to_integer(unsigned(byte_select(i*3+2 downto i*3)));
            sb(i*8+7 downto i*8):=bytes_in(bidx*8+7 downto bidx*8);
        end loop;
        for i in 0 to 3 loop
            hidx:=to_integer(unsigned(half_select(i*2+1 downto i*2)));
            sh(i*16+15 downto i*16):=halfwords_in(hidx*16+15 downto hidx*16);
        end loop;
        for row in 0 to 7 loop
            for col in 0 to 7 loop
                transposed((col*8+row)*8+7 downto (col*8+row)*8):=tile_in((row*8+col)*8+7 downto (row*8+col)*8);
            end loop;
        end loop;
        packed16<=p16; packed8<=p8; extended_bytes<=xb; extended_halfwords<=xh;
        shuffled_bytes<=sb; shuffled_halfwords<=sh; tile_transposed<=transposed;
    end process;
end architecture;
