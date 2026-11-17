library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity systolic_os_act_quant is
    port(clk, reset, start: in std_logic; matrix_a, matrix_b: in std_logic_vector(127 downto 0);
         bias: in std_logic_vector(511 downto 0); activation: in unsigned(1 downto 0); shift: in unsigned(4 downto 0);
         busy, done: out std_logic; accumulators: out std_logic_vector(511 downto 0);
         quantized: out std_logic_vector(127 downto 0));
end entity;
architecture rtl of systolic_os_act_quant is
    type bytes is array(0 to 15) of signed(7 downto 0);
    type words is array(0 to 15) of signed(31 downto 0);
    signal a_latched,b_latched: std_logic_vector(127 downto 0) := (others=>'0');
    signal bias_latched: std_logic_vector(511 downto 0) := (others=>'0');
    signal activation_latched: unsigned(1 downto 0) := (others=>'0');
    signal shift_latched: unsigned(4 downto 0) := (others=>'0');
    signal step: natural range 0 to 9 := 0;
    signal busy_r: std_logic := '0';
    signal a_pipe,b_pipe,a_in,b_in: bytes := (others=>(others=>'0'));
    signal acc: words := (others=>(others=>'0'));
begin
    busy<=busy_r;
    process(all)
        variable va,vb: bytes;
        variable out_acc: std_logic_vector(511 downto 0);
        variable out_q: std_logic_vector(127 downto 0);
        variable value: signed(32 downto 0);
        variable ai,bi: natural;
    begin
        va:=(others=>(others=>'0')); vb:=(others=>(others=>'0'));
        out_acc:=(others=>'0'); out_q:=(others=>'0');
        for row in 0 to 3 loop
            for col in 0 to 3 loop
                if col=0 then
                    if step>=row and step<row+4 then
                        ai:=row*4+(step-row); va(row*4+col):=signed(a_latched(ai*8+7 downto ai*8));
                    end if;
                else va(row*4+col):=a_pipe(row*4+col-1); end if;
                if row=0 then
                    if step>=col and step<col+4 then
                        bi:=(step-col)*4+col; vb(row*4+col):=signed(b_latched(bi*8+7 downto bi*8));
                    end if;
                else vb(row*4+col):=b_pipe((row-1)*4+col); end if;
            end loop;
        end loop;
        a_in<=va; b_in<=vb;
        for pos in 0 to 15 loop
            out_acc(pos*32+31 downto pos*32):=std_logic_vector(acc(pos));
            value:=resize(acc(pos),33)+resize(signed(bias_latched(pos*32+31 downto pos*32)),33);
            if activation_latched/=0 and value<0 then value:=(others=>'0'); end if;
            if activation_latched=2 and value>6 then value:=to_signed(6,33); end if;
            value:=shift_right(value,to_integer(shift_latched));
            if value>127 then out_q(pos*8+7 downto pos*8):=x"7f";
            elsif value< -128 then out_q(pos*8+7 downto pos*8):=x"80";
            else out_q(pos*8+7 downto pos*8):=std_logic_vector(value(7 downto 0)); end if;
        end loop;
        accumulators<=out_acc; quantized<=out_q;
    end process;
    process(clk)
    begin
        if rising_edge(clk) then
            if reset='1' then
                busy_r<='0'; done<='0'; step<=0; a_latched<=(others=>'0'); b_latched<=(others=>'0');
                bias_latched<=(others=>'0'); activation_latched<=(others=>'0'); shift_latched<=(others=>'0');
                a_pipe<=(others=>(others=>'0')); b_pipe<=(others=>(others=>'0')); acc<=(others=>(others=>'0'));
            else
                done<='0';
                if start='1' and busy_r='0' then
                    busy_r<='1'; step<=0; a_latched<=matrix_a; b_latched<=matrix_b; bias_latched<=bias;
                    activation_latched<=activation; shift_latched<=shift;
                    a_pipe<=(others=>(others=>'0')); b_pipe<=(others=>(others=>'0')); acc<=(others=>(others=>'0'));
                elsif busy_r='1' then
                    for pos in 0 to 15 loop
                        a_pipe(pos)<=a_in(pos); b_pipe(pos)<=b_in(pos);
                        acc(pos)<=acc(pos)+resize(a_in(pos)*b_in(pos),32);
                    end loop;
                    if step=9 then busy_r<='0'; done<='1'; else step<=step+1; end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
