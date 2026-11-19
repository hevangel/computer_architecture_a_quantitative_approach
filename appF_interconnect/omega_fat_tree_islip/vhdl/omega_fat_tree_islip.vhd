library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity omega8 is
    port (
        clk, reset : in std_logic;
        in_valid, in_tail : in std_logic_vector(7 downto 0);
        in_ready : out std_logic_vector(7 downto 0);
        in_dest : in std_logic_vector(23 downto 0);
        in_data : in std_logic_vector(127 downto 0);
        out_valid, out_tail : out std_logic_vector(7 downto 0);
        out_ready : in std_logic_vector(7 downto 0);
        out_data : out std_logic_vector(127 downto 0)
    );
end entity;
architecture rtl of omega8 is
    type addresses is array(0 to 23) of std_logic_vector(2 downto 0);
    type words is array(0 to 23) of std_logic_vector(15 downto 0);
    signal full, next_full, tail, next_tail, reserved, next_reserved : std_logic_vector(23 downto 0);
    signal side, next_side, rr, next_rr : std_logic_vector(23 downto 0);
    signal dest, next_dest : addresses;
    signal data, next_data : words;
    function bit_value(n : natural) return std_logic is
    begin
        if n mod 2=1 then return '1'; else return '0'; end if;
    end;
    function bit_index(b : std_logic) return natural is
    begin
        if b='1' then return 1; else return 0; end if;
    end;
begin
    in_ready <= not full(7 downto 0) when reset='0' else x"00";
    process(all)
        variable f, t, reserve, owner_side, pointers : std_logic_vector(23 downto 0);
        variable d : addresses;
        variable payload : words;
        variable slot, downstream, first_port, candidate : natural;
        variable selected : integer;
        variable credit : boolean;
    begin
        f:=full; t:=tail; reserve:=reserved; owner_side:=side; pointers:=rr;
        d:=dest; payload:=data;
        out_valid<=(others=>'0'); out_tail<=(others=>'0'); out_data<=(others=>'0');
        for stage in 0 to 2 loop
            for port_id in 0 to 7 loop
                slot:=8*stage+port_id;
                if stage=2 then
                    downstream:=0; credit:=out_ready(port_id)='1';
                else
                    downstream:=8*(stage+1)+(2*port_id mod 8)+port_id/4;
                    credit:=full(downstream)='0';
                end if;
                first_port:=8*stage+2*(port_id/2);
                selected:=-1;
                for option_id in 0 to 1 loop
                    if reserved(slot)='1' then candidate:=first_port+bit_index(side(slot));
                    else candidate:=first_port+(bit_index(rr(slot))+option_id) mod 2; end if;
                    if selected<0 and full(candidate)='1' and dest(candidate)(2-stage)=bit_value(port_id) then
                        selected:=candidate;
                    end if;
                end loop;
                if selected>=0 then
                    if stage=2 then
                        out_valid(port_id)<=not reset;
                        out_data(16*port_id+15 downto 16*port_id)<=data(selected);
                        out_tail(port_id)<=tail(selected);
                        if not credit and reserved(slot)='0' then
                            reserve(slot):='1'; owner_side(slot):=bit_value(selected);
                        end if;
                    end if;
                    if credit then
                        f(selected):='0';
                        reserve(slot):=not tail(selected); owner_side(slot):=bit_value(selected);
                        if tail(selected)='1' then pointers(slot):=not bit_value(selected); end if;
                        if stage/=2 then
                            f(downstream):='1'; d(downstream):=dest(selected);
                            payload(downstream):=data(selected); t(downstream):=tail(selected);
                        end if;
                    end if;
                end if;
            end loop;
        end loop;
        for i in 0 to 7 loop
            if in_valid(i)='1' and in_ready(i)='1' then
                f(i):='1'; d(i):=in_dest(3*i+2 downto 3*i);
                payload(i):=in_data(16*i+15 downto 16*i); t(i):=in_tail(i);
            end if;
        end loop;
        next_full<=f; next_tail<=t; next_reserved<=reserve; next_side<=owner_side;
        next_rr<=pointers; next_dest<=d; next_data<=payload;
    end process;
    process(clk)
    begin
        if rising_edge(clk) then
            if reset='1' then
                full<=(others=>'0'); tail<=(others=>'0'); reserved<=(others=>'0');
                side<=(others=>'0'); rr<=(others=>'0');
                dest<=(others=>(others=>'0')); data<=(others=>(others=>'0'));
            else
                full<=next_full; tail<=next_tail; reserved<=next_reserved;
                side<=next_side; rr<=next_rr; dest<=next_dest; data<=next_data;
            end if;
        end if;
    end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
entity islip8 is
    generic (ITERATIONS : positive := 4);
    port (clk, reset, advance : in std_logic;
          requests : in std_logic_vector(63 downto 0);
          connections : out std_logic_vector(63 downto 0));
end entity;
architecture rtl of islip8 is
    type indices is array(0 to 7) of integer range -1 to 7;
    signal grant_ptr, accept_ptr, next_grant, next_accept : indices := (others=>0);
begin
    process(all)
        variable matched_in, matched_out : std_logic_vector(7 downto 0);
        variable granted_by, g, a : indices;
        variable matched : std_logic_vector(63 downto 0);
        variable candidate, accepted : integer;
    begin
        matched:=(others=>'0'); matched_in:=(others=>'0'); matched_out:=(others=>'0');
        g:=grant_ptr; a:=accept_ptr;
        for iteration in 0 to ITERATIONS-1 loop
            for o in 0 to 7 loop
                granted_by(o):=-1;
                for offset in 0 to 7 loop
                    candidate:=(grant_ptr(o)+offset) mod 8;
                    if matched_out(o)='0' and matched_in(candidate)='0' and
                       requests(8*candidate+o)='1' and granted_by(o)<0 then
                        granted_by(o):=candidate;
                    end if;
                end loop;
            end loop;
            for i in 0 to 7 loop
                accepted:=-1;
                for offset in 0 to 7 loop
                    candidate:=(accept_ptr(i)+offset) mod 8;
                    if granted_by(candidate)=i and accepted<0 then accepted:=candidate; end if;
                end loop;
                if accepted>=0 then
                    matched(8*i+accepted):='1'; matched_in(i):='1'; matched_out(accepted):='1';
                    if iteration=0 then
                        g(accepted):=(i+1) mod 8; a(i):=(accepted+1) mod 8;
                    end if;
                end if;
            end loop;
        end loop;
        connections<=matched; next_grant<=g; next_accept<=a;
    end process;
    process(clk)
    begin
        if rising_edge(clk) then
            if reset='1' then grant_ptr<=(others=>0); accept_ptr<=(others=>0);
            elsif advance='1' then grant_ptr<=next_grant; accept_ptr<=next_accept; end if;
        end if;
    end process;
end architecture;
