library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity carry_skip16 is
    port(a, b: in std_logic_vector(15 downto 0); cin: in std_logic;
         sum: out std_logic_vector(15 downto 0); cout: out std_logic);
end entity;
architecture rtl of carry_skip16 is
begin
    process(all)
        variable c: std_logic_vector(4 downto 0);
        variable result: std_logic_vector(15 downto 0);
        variable local_sum: unsigned(4 downto 0);
    begin
        c := (others => '0'); result := (others => '0'); c(0) := cin;
        for g in 0 to 3 loop
            local_sum := ('0' & unsigned(a(4*g+3 downto 4*g))) +
                         ('0' & unsigned(b(4*g+3 downto 4*g)));
            if c(g) = '1' then local_sum := local_sum + 1; end if;
            result(4*g+3 downto 4*g) := std_logic_vector(local_sum(3 downto 0));
            if (a(4*g+3 downto 4*g) xor b(4*g+3 downto 4*g)) = "1111" then
                c(g+1) := c(g);
            else
                c(g+1) := local_sum(4);
            end if;
        end loop;
        sum <= result; cout <= c(4);
    end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity carry_select16 is
    port(a, b: in std_logic_vector(15 downto 0); cin: in std_logic;
         sum: out std_logic_vector(15 downto 0); cout: out std_logic);
end entity;
architecture rtl of carry_select16 is
begin
    process(all)
        variable c: std_logic_vector(4 downto 0);
        variable result: std_logic_vector(15 downto 0);
        variable zero_result, one_result, chosen: unsigned(4 downto 0);
    begin
        c := (others => '0'); result := (others => '0'); c(0) := cin;
        for g in 0 to 3 loop
            zero_result := ('0' & unsigned(a(4*g+3 downto 4*g))) +
                           ('0' & unsigned(b(4*g+3 downto 4*g)));
            one_result := zero_result + 1;
            if c(g) = '1' then chosen := one_result; else chosen := zero_result; end if;
            result(4*g+3 downto 4*g) := std_logic_vector(chosen(3 downto 0));
            c(g+1) := chosen(4);
        end loop;
        sum <= result; cout <= c(4);
    end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wallace8 is
    port(a, b: in std_logic_vector(7 downto 0); product: out std_logic_vector(15 downto 0));
end entity;
architecture rtl of wallace8 is
    subtype word is unsigned(15 downto 0);
    type words is array (natural range <>) of word;
    function csa_sum(x, y, z: word) return word is
    begin return x xor y xor z; end function;
    function csa_carry(x, y, z: word) return word is
    begin return shift_left((x and y) or (x and z) or (y and z), 1); end function;
begin
    process(all)
        variable p: words(0 to 7);
        variable s0, c0, s1, c1, s2, c2, s3, c3, s4, c4, s5, c5: word;
    begin
        for i in 0 to 7 loop
            if b(i) = '1' then p(i) := shift_left(resize(unsigned(a), 16), i);
            else p(i) := (others => '0'); end if;
        end loop;
        s0 := csa_sum(p(0),p(1),p(2)); c0 := csa_carry(p(0),p(1),p(2));
        s1 := csa_sum(p(3),p(4),p(5)); c1 := csa_carry(p(3),p(4),p(5));
        s2 := csa_sum(s0,c0,s1); c2 := csa_carry(s0,c0,s1);
        s3 := csa_sum(c1,p(6),p(7)); c3 := csa_carry(c1,p(6),p(7));
        s4 := csa_sum(s2,c2,s3); c4 := csa_carry(s2,c2,s3);
        s5 := csa_sum(s4,c4,c3); c5 := csa_carry(s4,c4,c3);
        product <= std_logic_vector(s5 + c5);
    end process;
end architecture;
