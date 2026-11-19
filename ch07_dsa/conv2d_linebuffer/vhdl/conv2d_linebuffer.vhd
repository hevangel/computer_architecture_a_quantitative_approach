library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity conv2d_linebuffer is
    generic(WIDTH: positive := 16; HEIGHT: positive := 16);
    port(clk, reset, in_valid: in std_logic; pixel: in signed(7 downto 0);
         kernel: in std_logic_vector(71 downto 0);
         out_valid: out std_logic; result: out signed(31 downto 0));
end entity;
architecture rtl of conv2d_linebuffer is
    type row_type is array(0 to WIDTH-1) of signed(7 downto 0);
    signal previous, older: row_type := (others=>(others=>'0'));
    signal top_l2, top_l1, mid_l2, mid_l1, bot_l2, bot_l1: signed(7 downto 0) := (others=>'0');
    signal x: natural range 0 to WIDTH-1 := 0;
    signal y: natural range 0 to HEIGHT-1 := 0;
    function product(a: signed(7 downto 0); b: std_logic_vector(7 downto 0)) return signed is
    begin return resize(a * signed(b),32); end function;
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if reset='1' then
                x<=0; y<=0; out_valid<='0'; result<=(others=>'0');
                top_l2<=(others=>'0'); top_l1<=(others=>'0'); mid_l2<=(others=>'0');
                mid_l1<=(others=>'0'); bot_l2<=(others=>'0'); bot_l1<=(others=>'0');
                previous<=(others=>(others=>'0')); older<=(others=>(others=>'0'));
            else
                out_valid<='0';
                if in_valid='1' then
                    if x>=2 and y>=2 then
                        result <= product(top_l2,kernel(7 downto 0)) + product(top_l1,kernel(15 downto 8)) + product(older(x),kernel(23 downto 16)) +
                                  product(mid_l2,kernel(31 downto 24)) + product(mid_l1,kernel(39 downto 32)) + product(previous(x),kernel(47 downto 40)) +
                                  product(bot_l2,kernel(55 downto 48)) + product(bot_l1,kernel(63 downto 56)) + product(pixel,kernel(71 downto 64));
                        out_valid<='1';
                    end if;
                    older(x)<=previous(x); previous(x)<=pixel;
                    top_l2<=top_l1; top_l1<=older(x);
                    mid_l2<=mid_l1; mid_l1<=previous(x);
                    bot_l2<=bot_l1; bot_l1<=pixel;
                    if x=WIDTH-1 then
                        x<=0; if y=HEIGHT-1 then y<=0; else y<=y+1; end if;
                    else x<=x+1; end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
