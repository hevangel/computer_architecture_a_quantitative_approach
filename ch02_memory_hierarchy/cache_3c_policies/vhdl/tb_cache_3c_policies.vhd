library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_cache_3c_policies is end;
architecture test of tb_cache_3c_policies is
 signal clk:std_logic:='0'; signal reset,valid:std_logic:='0'; signal address:unsigned(7 downto 0):=(others=>'0');
 type nums is array(0 to 10) of unsigned(31 downto 0); type kinds is array(0 to 10) of unsigned(1 downto 0);
 type ints is array(0 to 10) of natural; type row is array(0 to 2) of natural;
 type cases is array(0 to 10) of row; type expected_t is array(0 to 2) of cases;
 type kind_case is array(0 to 10) of std_logic_vector(511 downto 0); type kind_table is array(0 to 2) of kind_case;
 constant expected_kind:kind_table := (
  (x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff55", x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff55", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa55", x"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055", x"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055", x"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055", x"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055", x"22222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222255", x"82a088aa2088820a2820820a0a0aa2082882082282a88a0a0a0a82a8288208a822082a2a2a08208a88a888220822228a28820828282082a22a2088a088a0a055", x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff55", x"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff55"),
  (x"a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280955", x"a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288955", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa955", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa955", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa955", x"2280a8828aa20280888828880a88a08820228202208820a028a080828a080820a0820a0a820280aa282282022202222022202080a02808882888088882822155", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa8955", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa955", x"aa2a2282a88a8aaaa8aa2a0a2828a8a8a2a2a2288aa8a2a2a28aaa82a0a28aaaaa0a2aa0a82a22a22a28aa8aa2a8aaa8a2a0a2a82aaaaaa0aaa28aaa2a8a8155", x"a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288a2288955", x"a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280a0280955"),
  (x"aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2991a5155", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa999a5955", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa999a5955", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa999a5955", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa999a5955", x"2a2a0aaa2a22aa2a22aaa88a2aa0aa2aaaaaaa8aaaaaaa2aaa28222a28a2aa28a2aaaaaaaa22aa2aa2aa2a2aaaaa20aa2a82aaaaaaaaaaaaaa2aa8aa99985155", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa999a5955", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa999a5955", x"aaa8a2aa2aa2aaaaaa2a2aa2aaaaa2aa2aaaaaaa2aaaaaa2aaaaaaaaa2aaaaaaaaaaaaaaaaaaa2a2aaa2aaa2a2aaaa2aaaa2aaaaa2aaaaaa82aaa8aa999a5155", x"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa999a5955", x"aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2aa2991a5155"));
 constant sets:ints:=(4,2,1,1,1,1,1,1,1,2,4); constant ways:ints:=(1,2,3,4,4,4,4,3,3,2,1); constant policies:ints:=(0,0,0,0,1,2,3,3,2,3,3);
 constant expected:expected_t := (
  ((4,0,252), (4,0,252), (4,252,0), (4,0,0), (4,0,0), (4,0,0), (4,0,0), (4,126,0), (4,129,0), (4,0,252), (4,0,252)),
  ((5,101,0), (5,151,0), (5,251,0), (5,251,0), (5,251,0), (5,110,0), (5,250,0), (5,251,0), (5,185,0), (5,151,0), (5,101,0)),
  ((10,204,0), (10,246,0), (10,246,0), (10,246,0), (10,246,0), (10,201,0), (10,246,0), (10,246,0), (10,222,0), (10,246,0), (10,204,0)));
 signal hit:std_logic_vector(0 to 10); signal kind:kinds; signal ac,cc,kc,fc:nums;
begin
 clk<=not clk after 5 ns;
 gen:for i in 0 to 10 generate
  dut:entity work.cache_3c_policies generic map(sets(i),ways(i),policies(i))
   port map(clk,reset,valid,address,hit(i),kind(i),ac(i),cc(i),kc(i),fc(i));
 end generate;
 process
  variable a:integer; variable misses:ints;
 begin
  for trace in 0 to 2 loop
   misses:=(others=>0);
   wait until falling_edge(clk); reset<='1'; valid<='0'; wait until falling_edge(clk); reset<='0'; valid<='1';
   for i in 0 to 255 loop
    case trace is
     when 0=>a:=(i mod 4)*4;
     when 1=>a:=i mod 5;
     when others=>a:=to_integer(to_unsigned(i*13,16) xor to_unsigned(i/3,16)) mod 16;
    end case;
    address<=to_unsigned(a,8); wait until falling_edge(clk);
    for d in 0 to 10 loop
     assert (hit(d)='1')=(kind(d)=0) report "hit/classification disagreement" severity failure;
     assert kind(d)=unsigned(expected_kind(trace)(d)(2*i+1 downto 2*i)) report "per-access classification" severity failure;
     if hit(d)='0' then misses(d):=misses(d)+1; end if;
    end loop;
   end loop;
   valid<='0';
   for d in 0 to 10 loop
    assert ac(d)=256 and cc(d)=expected(trace)(d)(0) and kc(d)=expected(trace)(d)(1) and fc(d)=expected(trace)(d)(2)
      report "3C totals: trace " & integer'image(trace) & " config " & integer'image(d) & " got " & integer'image(to_integer(cc(d))) & "/" & integer'image(to_integer(kc(d))) & "/" & integer'image(to_integer(fc(d))) severity failure;
    assert cc(d)+kc(d)+fc(d)=misses(d) report "invalid totals" severity failure;
   end loop;
   if trace=0 then assert fc(3)<fc(0) report "associativity conflict comparison" severity failure; end if;
  end loop;
  report "TEST PASSED"; finish;
 end process;
 process begin wait for 50 us; assert false report "timeout" severity failure; wait; end process;
end architecture;
