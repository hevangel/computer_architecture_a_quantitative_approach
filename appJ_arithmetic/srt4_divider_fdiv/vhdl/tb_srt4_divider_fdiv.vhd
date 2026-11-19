library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;
use std.env.all;

entity tb_srt4_divider_fdiv is end entity;
architecture test of tb_srt4_divider_fdiv is
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal start : std_logic := '0';
    signal numerator, denominator : unsigned(31 downto 0) := (others=>'0');
    signal busy, done, dz, hit, buggy_busy, buggy_done, buggy_dz, buggy_hit : std_logic;
    signal q, r, buggy_q, buggy_r : unsigned(31 downto 0);
    signal m, buggy_m : signed(65 downto 0);
    signal e, buggy_e : signed(6 downto 0);
begin
    clk<=not clk after 5 ns;
    good: entity work.srt4_divider_fdiv port map(clk,reset,start,numerator,denominator,busy,done,dz,hit,q,r,m,e);
    bad: entity work.srt4_divider_fdiv generic map(PENTIUM_FDIV_BUG=>true)
        port map(clk,reset,start,numerator,denominator,buggy_busy,buggy_done,buggy_dz,buggy_hit,
                 buggy_q,buggy_r,buggy_m,buggy_e);
    process
        file vectors : text open read_mode is "../../../../appJ_arithmetic/srt4_divider_fdiv/vectors.txt";
        variable row : line;
        variable av,bv,expected_q,expected_r : std_logic_vector(31 downto 0);
        variable expected_m : std_logic_vector(71 downto 0);
        variable expected_e : integer;
        variable n,latency : natural := 0;
        procedure tick is
        begin wait until rising_edge(clk); wait for 1 ns; end;
    begin
        tick; reset<='0';
        while not endfile(vectors) loop
            readline(vectors,row);
            hread(row,av); hread(row,bv); hread(row,expected_q); hread(row,expected_r);
            hread(row,expected_m); read(row,expected_e);
            numerator<=unsigned(av); denominator<=unsigned(bv);
            start<='1'; tick; start<='0'; latency:=0;
            while done/='1' and latency<34 loop
                assert busy='1' and buggy_busy='1' and buggy_done='0' report "busy mismatch" severity failure;
                tick; latency:=latency+1;
            end loop;
            assert done='1' and buggy_done='1' and busy='0' and buggy_busy='0' severity failure;
            if unsigned(av)=0 or unsigned(bv)=0 then
                assert latency=0 report "zero operand latency" severity failure;
            else
                assert latency=33 report "radix-4 cadence" severity failure;
            end if;
            assert q=unsigned(expected_q) and r=unsigned(expected_r) and m=signed(expected_m(65 downto 0)) and
                   to_integer(e)=expected_e and (dz='1')=(unsigned(bv)=0) and hit='0'
                report "arithmetic mismatch at vector " & integer'image(n) severity failure;
            if n=0 then
                assert buggy_hit='1' and buggy_m/=m report "missing FDIV precision loss" severity failure;
            end if;
            if buggy_hit='0' then
                assert buggy_q=q and buggy_r=r and buggy_m=m and buggy_e=e and buggy_dz=dz
                    report "fault changed an unaffected vector" severity failure;
            end if;
            n:=n+1;
        end loop;
        assert n=577 report "wrong vector count" severity failure;
        tick;
        assert done='0' and buggy_done='0' report "response not a pulse" severity failure;
        report "TEST PASSED (" & integer'image(n) & " vectors)";
        finish;
    end process;
end architecture;
