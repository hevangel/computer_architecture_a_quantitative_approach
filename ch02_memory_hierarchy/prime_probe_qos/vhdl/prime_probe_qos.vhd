library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity prime_probe_qos is
    generic(HIT_CYCLES: positive := 1; MISS_CYCLES: positive := 5);
    port(clk, reset, partition_enable, req_valid, domain_id: in std_logic;
         line_address: in unsigned(31 downto 0);
         req_ready, response_valid, response_hit: out std_logic;
         response_latency, spy_hits, spy_misses: out unsigned(31 downto 0));
end entity;
architecture rtl of prime_probe_qos is
    type tags_type is array(0 to 3) of unsigned(31 downto 0);
    signal tags: tags_type := (others=>(others=>'0'));
    signal valid_bits: std_logic_vector(3 downto 0) := (others=>'0');
    signal partitioned, next_victim, next_spy: std_logic := '0';
    signal next_shared: unsigned(1 downto 0) := (others=>'0');
    signal remaining: natural range 0 to integer'high := 0;
begin
    req_ready <= '1' when remaining=0 else '0';
    process(clk)
        variable found: integer range -1 to 3;
        variable chosen: integer range 0 to 3;
    begin
        if rising_edge(clk) then
            if reset='1' then
                partitioned <= partition_enable; valid_bits <= (others=>'0'); tags <= (others=>(others=>'0'));
                next_shared <= (others=>'0'); next_victim <= '0'; next_spy <= '0'; remaining <= 0;
                response_valid <= '0'; response_hit <= '0'; response_latency <= (others=>'0');
                spy_hits <= (others=>'0'); spy_misses <= (others=>'0');
            else
                response_valid <= '0';
                if remaining/=0 then
                    remaining <= remaining-1;
                    if remaining=1 then response_valid <= '1'; end if;
                elsif req_valid='1' then
                    found := -1;
                    for i in 0 to 3 loop
                        if (partitioned='0' or (domain_id='1' and i>=2) or (domain_id='0' and i<2)) and
                           valid_bits(i)='1' and tags(i)=line_address then found := i; end if;
                    end loop;
                    if found>=0 then
                        response_hit <= '1'; response_latency <= to_unsigned(HIT_CYCLES,32); remaining <= HIT_CYCLES;
                        if domain_id='1' then spy_hits <= spy_hits+1; end if;
                    else
                        if partitioned='0' then chosen := to_integer(next_shared); next_shared <= next_shared+1;
                        elsif domain_id='1' then
                            if next_spy='0' then chosen := 2; else chosen := 3; end if;
                            next_spy <= not next_spy;
                        else
                            if next_victim='0' then chosen := 0; else chosen := 1; end if;
                            next_victim <= not next_victim;
                        end if;
                        tags(chosen) <= line_address; valid_bits(chosen) <= '1';
                        response_hit <= '0'; response_latency <= to_unsigned(MISS_CYCLES,32); remaining <= MISS_CYCLES;
                        if domain_id='1' then spy_misses <= spy_misses+1; end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
