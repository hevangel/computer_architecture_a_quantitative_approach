library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity srt4_divider_fdiv is
    generic(PENTIUM_FDIV_BUG : boolean := false);
    port (
        clk, reset, start : in std_logic;
        numerator, denominator : in unsigned(31 downto 0);
        busy, done, divide_by_zero, fault_hit : out std_logic;
        quotient, remainder : out unsigned(31 downto 0);
        mantissa : out signed(65 downto 0);
        exponent : out signed(6 downto 0)
    );
end entity;

architecture rtl of srt4_divider_fdiv is
    type table is array(0 to 2047) of integer range -2 to 2;
    impure function read_selection return table is
        file source : text open read_mode is "../../../../appJ_arithmetic/srt4_divider_fdiv/selection.txt";
        variable row : line;
        variable bits : bit_vector(2 downto 0);
        variable values : table;
    begin
        for index in values'range loop
            readline(source,row); read(row,bits);
            values(index):=to_integer(unsigned(to_stdlogicvector(bits)))-2;
        end loop;
        return values;
    end function;
    constant selection : table := read_selection;
    function top_bit(word : unsigned(31 downto 0)) return natural is
    begin
        for i in 31 downto 0 loop
            if word(i)='1' then return i; end if;
        end loop;
        return 0;
    end function;
begin
    process(clk)
        variable sum_word, carry_word, divisor, term, multiple, new_sum, new_carry : unsigned(34 downto 0);
        variable saved_n, saved_d : unsigned(31 downto 0);
        variable prefix, prefix_minus_one, next_prefix, next_minus, integer_part : signed(66 downto 0);
        variable row : signed(6 downto 0);
        variable residual : signed(64 downto 0);
        variable product : unsigned(63 downto 0);
        variable iteration, hi_n, hi_d, column, digit : integer;
        variable omitted : boolean;
    begin
        if rising_edge(clk) then
            done<='0';
            if reset='1' then
                busy<='0'; divide_by_zero<='0'; fault_hit<='0';
                quotient<=(others=>'0'); remainder<=(others=>'0'); mantissa<=(others=>'0'); exponent<=(others=>'0');
                sum_word:=(others=>'0'); carry_word:=(others=>'0'); divisor:=(others=>'0');
                saved_n:=(others=>'0'); saved_d:=(others=>'0'); prefix:=(others=>'0');
                prefix_minus_one:=(others=>'1'); iteration:=0;
            elsif busy='0' and start='1' then
                fault_hit<='0';
                if denominator=0 then
                    divide_by_zero<='1'; done<='1';
                    quotient<=(others=>'1'); remainder<=numerator; mantissa<=(others=>'0'); exponent<=(others=>'0');
                elsif numerator=0 then
                    divide_by_zero<='0'; done<='1';
                    quotient<=(others=>'0'); remainder<=(others=>'0'); mantissa<=(others=>'0'); exponent<=(others=>'0');
                else
                    hi_n:=top_bit(numerator); hi_d:=top_bit(denominator);
                    exponent<=to_signed(hi_n-hi_d,7);
                    sum_word:=shift_left(resize(numerator,35),31-hi_n);
                    divisor:=shift_left(resize(denominator,35),31-hi_d);
                    carry_word:=(others=>'0'); prefix:=(others=>'0'); prefix_minus_one:=(others=>'1');
                    iteration:=0; saved_n:=numerator; saved_d:=denominator;
                    busy<='1'; divide_by_zero<='0';
                end if;
            elsif busy='1' then
                row:=signed(sum_word(34 downto 28))+signed(carry_word(34 downto 28));
                column:=to_integer(divisor(31 downto 27));
                digit:=selection(128*(column-16)+64+to_integer(row));
                omitted:=PENTIUM_FDIV_BUG and (column+1) mod 3=0 and to_integer(row)=4*(column+1)/3-1;
                if omitted then digit:=0; fault_hit<='1'; end if;
                case abs(digit) is
                    when 2 => multiple:=shift_left(divisor,1);
                    when 1 => multiple:=divisor;
                    when others => multiple:=(others=>'0');
                end case;
                if digit>0 then term:=not multiple; else term:=multiple; end if;
                new_sum:=sum_word xor carry_word xor term;
                new_carry:=shift_left((sum_word and carry_word) or (sum_word and term) or (carry_word and term),1);
                if digit>0 then new_carry(0):='1'; end if;
                sum_word:=shift_left(new_sum,2); carry_word:=shift_left(new_carry,2);
                if digit>=0 then next_prefix:=shift_left(prefix,2);
                else next_prefix:=shift_left(prefix_minus_one,2); end if;
                next_prefix(1 downto 0):=signed(to_unsigned(digit mod 4,2));
                if digit>0 then next_minus:=shift_left(prefix,2);
                else next_minus:=shift_left(prefix_minus_one,2); end if;
                next_minus(1 downto 0):=signed(to_unsigned((digit-1) mod 4,2));
                prefix:=next_prefix; prefix_minus_one:=next_minus;
                if iteration=32 then
                    mantissa<=next_prefix(65 downto 0);
                    integer_part:=shift_right(next_prefix,64-to_integer(exponent));
                    product:=unsigned(integer_part(31 downto 0))*saved_d;
                    residual:=signed(resize(saved_n,65))-signed(resize(product,65));
                    if fault_hit='0' and not omitted then
                        if residual<0 then
                            integer_part:=integer_part-1; residual:=residual+signed(resize(saved_d,65));
                        elsif residual>=signed(resize(saved_d,65)) then
                            integer_part:=integer_part+1; residual:=residual-signed(resize(saved_d,65));
                        end if;
                    end if;
                    quotient<=unsigned(integer_part(31 downto 0)); remainder<=unsigned(residual(31 downto 0));
                    busy<='0'; done<='1';
                else iteration:=iteration+1; end if;
            end if;
        end if;
    end process;
end architecture;
