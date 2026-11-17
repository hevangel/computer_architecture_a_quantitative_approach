library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity stream_buffer is
    port(clk, reset, req_valid, prefetch_enable: in std_logic;
         req_line: in unsigned(31 downto 0);
         response_valid: out std_logic; response_data: out std_logic_vector(31 downto 0);
         cycles, l1_hits, l1_misses, demand_reads, prefetch_hits, prefetch_reads: out unsigned(31 downto 0));
end entity;

architecture rtl of stream_buffer is
    type words is array(natural range <>) of unsigned(31 downto 0);
    signal l1_valid: std_logic_vector(7 downto 0) := (others=>'0');
    signal l1_tag, l1_data: words(0 to 7) := (others=>(others=>'0'));
    signal fifo_valid: std_logic := '0';
    signal fifo_tag, fifo_data: words(0 to 3) := (others=>(others=>'0'));
    function memory_data(address: unsigned(31 downto 0)) return unsigned is
    begin return address xor unsigned'(x"a5c39e71"); end function;
begin
    process(clk)
        variable idx: natural range 0 to 7;
    begin
        if rising_edge(clk) then
            if reset='1' then
                l1_valid <= (others=>'0'); fifo_valid <= '0'; response_valid <= '0';
                response_data <= (others=>'0'); cycles <= (others=>'0'); l1_hits <= (others=>'0');
                l1_misses <= (others=>'0'); demand_reads <= (others=>'0');
                prefetch_hits <= (others=>'0'); prefetch_reads <= (others=>'0');
                l1_tag <= (others=>(others=>'0')); l1_data <= (others=>(others=>'0'));
                fifo_tag <= (others=>(others=>'0')); fifo_data <= (others=>(others=>'0'));
            else
                cycles <= cycles + 1; response_valid <= req_valid;
                if prefetch_enable='0' then fifo_valid <= '0'; end if;
                if req_valid='1' then
                    idx := to_integer(req_line(2 downto 0));
                    if l1_valid(idx)='1' and l1_tag(idx)=req_line then
                        l1_hits <= l1_hits + 1; response_data <= std_logic_vector(l1_data(idx));
                    else
                        l1_misses <= l1_misses + 1; l1_valid(idx) <= '1'; l1_tag(idx) <= req_line;
                        if prefetch_enable='1' and fifo_valid='1' and fifo_tag(0)=req_line then
                            prefetch_hits <= prefetch_hits + 1;
                            response_data <= std_logic_vector(fifo_data(0)); l1_data(idx) <= fifo_data(0);
                            for i in 0 to 2 loop fifo_tag(i) <= fifo_tag(i+1); fifo_data(i) <= fifo_data(i+1); end loop;
                            fifo_tag(3) <= fifo_tag(3) + 1; fifo_data(3) <= memory_data(fifo_tag(3) + 1);
                            prefetch_reads <= prefetch_reads + 1;
                        else
                            demand_reads <= demand_reads + 1;
                            response_data <= std_logic_vector(memory_data(req_line)); l1_data(idx) <= memory_data(req_line);
                            if prefetch_enable='1' then
                                fifo_valid <= '1';
                                for i in 0 to 3 loop
                                    fifo_tag(i) <= req_line + (i+1);
                                    fifo_data(i) <= memory_data(req_line + (i+1));
                                end loop;
                                prefetch_reads <= prefetch_reads + 4;
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
