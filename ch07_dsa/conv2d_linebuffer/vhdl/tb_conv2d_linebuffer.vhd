library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_conv2d_linebuffer is end entity;
architecture test of tb_conv2d_linebuffer is
    signal clk: std_logic := '0';
    signal reset: std_logic := '1';
    signal in_valid: std_logic := '0';
    signal pixel: signed(7 downto 0) := (others=>'0');
    signal kernel: std_logic_vector(71 downto 0) := (others=>'0');
    signal out_valid: std_logic;
    signal result: signed(31 downto 0);
begin
    clk <= not clk after 5 ns;
    dut: entity work.conv2d_linebuffer port map(clk,reset,in_valid,pixel,kernel,out_valid,result);
    process
        type weights_type is array(0 to 8) of integer;
        constant weights: weights_type := (-2,1,3,0,-1,2,1,-3,2);
        file pf, ef: text;
        variable status: file_open_status;
        variable input_line, output_line: line;
        variable value, expected, outputs: integer;
    begin
        for i in 0 to 8 loop kernel(i*8+7 downto i*8)<=std_logic_vector(to_signed(weights(i),8)); end loop;
        wait until falling_edge(clk); reset<='0';
        for frame in 0 to 1 loop
            file_open(status,pf,"../../../../ch07_dsa/conv2d_linebuffer/pixels.txt",read_mode);
            assert status=open_ok report "TEST FAILED: input file" severity failure;
            file_open(status,ef,"../../../../ch07_dsa/conv2d_linebuffer/expected.txt",read_mode);
            assert status=open_ok report "TEST FAILED: expected file" severity failure;
            outputs:=0;
            for i in 0 to 255 loop
                assert not endfile(pf) report "TEST FAILED: input vector" severity failure;
                readline(pf,input_line); read(input_line,value);
                in_valid<='1'; pixel<=to_signed(value,8); wait until falling_edge(clk);
                assert (out_valid='1')=((i/16>=2) and (i mod 16>=2)) report "TEST FAILED: valid" severity failure;
                if out_valid='1' then
                    assert not endfile(ef) report "TEST FAILED: missing output vector" severity failure;
                    readline(ef,output_line); read(output_line,expected);
                    assert result=to_signed(expected,32) report "TEST FAILED: output value" severity failure;
                    outputs:=outputs+1;
                end if;
                if i mod 17=0 and i/=255 then
                    in_valid<='0'; wait until falling_edge(clk);
                    assert out_valid='0' report "TEST FAILED: stalled valid" severity failure;
                end if;
            end loop;
            assert outputs=196 and endfile(ef) report "TEST FAILED: output count" severity failure;
            file_close(pf); file_close(ef);
        end loop;
        report "TEST PASSED"; finish;
    end process;
end architecture;
