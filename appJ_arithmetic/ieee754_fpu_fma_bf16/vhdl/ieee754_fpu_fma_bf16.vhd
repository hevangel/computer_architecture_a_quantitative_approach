library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ieee754_fpu_fma_bf16 is
    port (
        op, format, rounding : in unsigned(1 downto 0);
        a, b, c : in unsigned(31 downto 0);
        scale_a, scale_b : in signed(7 downto 0);
        result : out unsigned(31 downto 0);
        flags : out unsigned(4 downto 0)
    );
end entity;

architecture exact_datapath of ieee754_fpu_fma_bf16 is
    constant WIDTH : positive := 1112;
    constant BIAS : integer := 554;
    subtype word is unsigned(31 downto 0);
    subtype wide is unsigned(WIDTH-1 downto 0);
    subtype significand is unsigned(23 downto 0);
    type operand is record
        sign : std_logic;
        exponent : integer;
        magnitude : significand;
        nan, snan, inf, zero : boolean;
    end record;

    function expand(bits : word; fmt : unsigned(1 downto 0)) return word is
        variable exp_field, frac, mantissa, base, highest : integer;
        variable expanded : word := (others => '0');
    begin
        if fmt = 0 then return bits; end if;
        if fmt = 1 then return bits(15 downto 0) & x"0000"; end if;
        expanded(31) := bits(7);
        if fmt = 2 then
            exp_field := to_integer(bits(6 downto 2));
            frac := to_integer(bits(1 downto 0));
            if exp_field = 31 then
                expanded(30 downto 23) := x"ff";
                expanded(22 downto 21) := bits(1 downto 0);
                return expanded;
            end if;
            if exp_field = 0 then mantissa := frac; base := -16;
            else mantissa := 4 + frac; base := exp_field - 17; end if;
        else
            exp_field := to_integer(bits(6 downto 3));
            frac := to_integer(bits(2 downto 0));
            if exp_field = 15 and frac = 7 then
                expanded(30 downto 0) := to_unsigned(16#7fc00000#, 31);
                return expanded;
            end if;
            if exp_field = 0 then mantissa := frac; base := -9;
            else mantissa := 8 + frac; base := exp_field - 10; end if;
        end if;
        if mantissa /= 0 then
            highest := 0;
            for k in 0 to 3 loop
                if mantissa >= 2**k then highest := k; end if;
            end loop;
            expanded(30 downto 23) := to_unsigned(base + highest + 127, 8);
            expanded(22 downto 0) := shift_left(to_unsigned(mantissa, 23), 23-highest);
        end if;
        return expanded;
    end function;

    function decode(bits : word) return operand is
        variable x : operand;
        variable exp_field : integer;
    begin
        exp_field := to_integer(bits(30 downto 23));
        x.sign := bits(31);
        x.magnitude := '0' & bits(22 downto 0);
        if exp_field = 0 then x.exponent := -149;
        else x.exponent := exp_field - 150; x.magnitude(23) := '1'; end if;
        x.nan := exp_field = 255 and bits(22 downto 0) /= 0;
        x.snan := x.nan and bits(22) = '0';
        x.inf := exp_field = 255 and bits(22 downto 0) = 0;
        x.zero := bits(30 downto 0) = 0;
        return x;
    end function;
begin
    process(all)
        variable x, y, z : operand;
        variable first_term, second_term, magnitude : wide;
        variable sign1, sign2, out_sign : std_logic;
        variable inf1, inf2, add_second, invalid, any_nan : boolean;
        variable exponent, highest, cutoff : integer;
        variable q : unsigned(24 downto 0);
        variable guard_bit, sticky, inexact, increment, to_inf : boolean;
        variable out_bits : word;
        variable out_flags : unsigned(4 downto 0);
    begin
        out_bits := (others => '0');
        out_flags := (others => '0');
        if not is_x(std_logic_vector(op & format & rounding & a & b & c & unsigned(scale_a) & unsigned(scale_b))) then
            if op = 2 then
                x := decode(expand(a, format));
                y := decode(expand(b, format));
                if format /= 0 then
                    x.exponent := x.exponent + to_integer(scale_a);
                    y.exponent := y.exponent + to_integer(scale_b);
                end if;
            else
                x := decode(a);
                y := decode(b);
            end if;
            z := decode(c);
            add_second := op /= 1;
            any_nan := x.nan or y.nan or (op = 2 and z.nan);
            invalid := x.snan or y.snan or (op = 2 and z.snan);
            if op = 0 then
                first_term := shift_left(resize(x.magnitude, WIDTH), x.exponent + BIAS);
                second_term := shift_left(resize(y.magnitude, WIDTH), y.exponent + BIAS);
                sign1 := x.sign;
                sign2 := y.sign;
                inf1 := x.inf;
                inf2 := y.inf;
            else
                first_term := shift_left(resize(x.magnitude * y.magnitude, WIDTH), x.exponent + y.exponent + BIAS);
                second_term := shift_left(resize(z.magnitude, WIDTH), z.exponent + BIAS);
                sign1 := x.sign xor y.sign;
                sign2 := z.sign;
                inf1 := x.inf or y.inf;
                inf2 := z.inf;
                invalid := invalid or (x.inf and y.zero) or (y.inf and x.zero);
            end if;
            invalid := invalid or (add_second and inf1 and inf2 and sign1 /= sign2 and not any_nan);
            if any_nan or invalid then
                out_bits := x"7fc00000";
                if invalid then out_flags(4) := '1'; end if;
            elsif inf1 or (add_second and inf2) then
                out_bits := x"7f800000";
                if inf1 then out_bits(31) := sign1;
                else out_bits(31) := sign2; end if;
            else
                if not add_second then magnitude := first_term; out_sign := sign1;
                elsif sign1 = sign2 then magnitude := first_term + second_term; out_sign := sign1;
                elsif first_term > second_term then magnitude := first_term - second_term; out_sign := sign1;
                elsif second_term > first_term then magnitude := second_term - first_term; out_sign := sign2;
                else
                    magnitude := (others => '0');
                    if rounding = 3 then out_sign := '1'; else out_sign := '0'; end if;
                end if;
                out_bits(31) := out_sign;
                if magnitude /= 0 then
                    highest := 0;
                    for k in 0 to WIDTH-1 loop
                        if magnitude(k) = '1' then highest := k; end if;
                    end loop;
                    exponent := highest - BIAS;
                    if exponent < -126 then cutoff := BIAS - 149;
                    else cutoff := highest - 23; end if;
                    q := resize(shift_right(magnitude, cutoff), q'length);
                    guard_bit := magnitude(cutoff-1) = '1';
                    sticky := false;
                    for k in 0 to WIDTH-1 loop
                        if k < cutoff-1 and magnitude(k) = '1' then sticky := true; end if;
                    end loop;
                    inexact := guard_bit or sticky;
                    case to_integer(rounding) is
                        when 0 => increment := guard_bit and (sticky or q(0) = '1');
                        when 1 => increment := false;
                        when 2 => increment := inexact and out_sign = '0';
                        when others => increment := inexact and out_sign = '1';
                    end case;
                    if increment then q := q + 1; end if;
                    if exponent >= -126 and q(24) = '1' then
                        q := shift_right(q, 1);
                        exponent := exponent + 1;
                    end if;
                    if exponent > 127 then
                        to_inf := rounding = 0 or (rounding = 2 and out_sign = '0') or
                                  (rounding = 3 and out_sign = '1');
                        if to_inf then out_bits(30 downto 0) := to_unsigned(16#7f800000#, 31);
                        else out_bits(30 downto 0) := to_unsigned(16#7f7fffff#, 31); end if;
                        out_flags := "00101";
                    else
                        out_bits(22 downto 0) := q(22 downto 0);
                        if exponent >= -126 then
                            out_bits(30 downto 23) := to_unsigned(exponent + 127, 8);
                        elsif q(23) = '1' then
                            out_bits(30 downto 23) := x"01";
                        elsif inexact then
                            out_flags(1) := '1';
                        end if;
                        if inexact then out_flags(0) := '1'; end if;
                    end if;
                end if;
            end if;
        end if;
        result <= out_bits;
        flags <= out_flags;
    end process;
end architecture;
