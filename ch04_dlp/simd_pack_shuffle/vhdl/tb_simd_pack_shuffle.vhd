library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_simd_pack_shuffle is end entity;
architecture test of tb_simd_pack_shuffle is
    signal words_in: std_logic_vector(255 downto 0) := (others=>'0');
    signal bytes_in: std_logic_vector(63 downto 0) := (others=>'0');
    signal halfwords_in: std_logic_vector(127 downto 0) := (others=>'0');
    signal signed_extend: std_logic := '0';
    signal byte_select: std_logic_vector(23 downto 0) := (others=>'0');
    signal half_select: std_logic_vector(7 downto 0) := (others=>'0');
    signal tile_in: std_logic_vector(511 downto 0) := (others=>'0');
    signal packed16, extended_bytes: std_logic_vector(127 downto 0);
    signal packed8, shuffled_bytes, shuffled_halfwords: std_logic_vector(63 downto 0);
    signal extended_halfwords: std_logic_vector(255 downto 0);
    signal tile_transposed: std_logic_vector(511 downto 0);
begin
    dut: entity work.simd_pack_shuffle port map(words_in,bytes_in,halfwords_in,signed_extend,byte_select,half_select,tile_in,
        packed16,packed8,extended_bytes,extended_halfwords,shuffled_bytes,shuffled_halfwords,tile_transposed);
    process
        type numbers is array(0 to 7) of integer;
        file vectors: text;
        variable status: file_open_status;
        variable line_buffer: line;
        variable value, e16, e8: integer;
        variable expected16, expected8: numbers;
    begin
        file_open(status,vectors,"../../../../ch04_dlp/simd_pack_shuffle/golden.txt",read_mode);
        assert status=open_ok report "TEST FAILED: missing golden vectors" severity failure;
        for i in 0 to 7 loop
            assert not endfile(vectors) report "TEST FAILED: missing vector" severity failure;
            readline(vectors,line_buffer); read(line_buffer,value); read(line_buffer,e16); read(line_buffer,e8);
            words_in(i*32+31 downto i*32)<=std_logic_vector(to_signed(value,32)); expected16(i):=e16; expected8(i):=e8;
            bytes_in(i*8+7 downto i*8)<=std_logic_vector(to_unsigned((i*37+128) mod 256,8));
            halfwords_in(i*16+15 downto i*16)<=std_logic_vector(to_unsigned((i*9001+32768) mod 65536,16));
            byte_select(i*3+2 downto i*3)<=std_logic_vector(to_unsigned(7-i,3));
        end loop;
        file_close(vectors);
        for i in 0 to 3 loop half_select(i*2+1 downto i*2)<=std_logic_vector(to_unsigned(3-i,2)); end loop;
        for row in 0 to 7 loop
            for col in 0 to 7 loop tile_in((row*8+col)*8+7 downto (row*8+col)*8)<=std_logic_vector(to_unsigned(row*8+col,8)); end loop;
        end loop;
        wait for 1 ns;
        for i in 0 to 7 loop
            assert signed(packed16(i*16+15 downto i*16))=to_signed(expected16(i),16) and
                   signed(packed8(i*8+7 downto i*8))=to_signed(expected8(i),8) and
                   unsigned(extended_bytes(i*16+15 downto i*16))=resize(unsigned(bytes_in(i*8+7 downto i*8)),16) and
                   unsigned(extended_halfwords(i*32+31 downto i*32))=resize(unsigned(halfwords_in(i*16+15 downto i*16)),32) and
                   shuffled_bytes(i*8+7 downto i*8)=bytes_in((7-i)*8+7 downto (7-i)*8)
                report "TEST FAILED: narrowing, zero extension or byte shuffle" severity failure;
        end loop;
        for i in 0 to 3 loop
            assert shuffled_halfwords(i*16+15 downto i*16)=halfwords_in((3-i)*16+15 downto (3-i)*16)
                report "TEST FAILED: halfword shuffle" severity failure;
        end loop;
        for row in 0 to 7 loop
            for col in 0 to 7 loop
                assert unsigned(tile_transposed((col*8+row)*8+7 downto (col*8+row)*8))=to_unsigned(row*8+col,8)
                    report "TEST FAILED: transpose" severity failure;
            end loop;
        end loop;
        signed_extend<='1'; byte_select<=(others=>'0'); half_select<=(others=>'0'); wait for 1 ns;
        for i in 0 to 7 loop
            assert signed(extended_bytes(i*16+15 downto i*16))=resize(signed(bytes_in(i*8+7 downto i*8)),16) and
                   signed(extended_halfwords(i*32+31 downto i*32))=resize(signed(halfwords_in(i*16+15 downto i*16)),32) and
                   shuffled_bytes(i*8+7 downto i*8)=bytes_in(7 downto 0)
                report "TEST FAILED: sign extension or broadcast" severity failure;
        end loop;
        for i in 0 to 3 loop
            assert shuffled_halfwords(i*16+15 downto i*16)=halfwords_in(15 downto 0)
                report "TEST FAILED: halfword broadcast" severity failure;
        end loop;
        report "TEST PASSED"; finish;
    end process;
end architecture;
