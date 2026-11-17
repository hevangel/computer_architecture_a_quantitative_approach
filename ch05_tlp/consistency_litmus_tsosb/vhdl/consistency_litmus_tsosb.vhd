library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity consistency_litmus_tsosb is
    port(clk, reset, mode_tso, cmd_valid, core_id: in std_logic; cmd: in unsigned(1 downto 0);
         address: in std_logic; write_data: in unsigned(31 downto 0);
         accepted, read_valid: out std_logic; read_data, mem_x, mem_y: out unsigned(31 downto 0);
         pending_core0, pending_core1: out unsigned(1 downto 0));
end entity;
architecture rtl of consistency_litmus_tsosb is
    type words is array(0 to 1) of unsigned(31 downto 0);
    type word_queue is array(0 to 1,0 to 1) of unsigned(31 downto 0);
    type address_queue is array(0 to 1,0 to 1) of std_logic;
    type counts is array(0 to 1) of natural range 0 to 2;
    signal memory: words := (others=>(others=>'0'));
    signal data_q: word_queue := (others=>(others=>(others=>'0')));
    signal addr_q: address_queue := (others=>(others=>'0'));
    signal count: counts := (others=>0);
    signal tso: std_logic := '0';
    function index_of(bit_value: std_logic) return natural is
    begin if bit_value='1' then return 1; else return 0; end if; end function;
begin
    mem_x<=memory(0); mem_y<=memory(1);
    pending_core0<=to_unsigned(count(0),2); pending_core1<=to_unsigned(count(1),2);
    process(clk)
        variable c, a: natural range 0 to 1;
    begin
        if rising_edge(clk) then
            if reset='1' then
                tso<=mode_tso; accepted<='0'; read_valid<='0'; read_data<=(others=>'0');
                memory<=(others=>(others=>'0')); count<=(others=>0);
                data_q<=(others=>(others=>(others=>'0'))); addr_q<=(others=>(others=>'0'));
            else
                accepted<='0'; read_valid<='0';
                if cmd_valid='1' then
                    c:=index_of(core_id); a:=index_of(address);
                    case to_integer(cmd) is
                        when 0 =>
                            if tso='0' then memory(a)<=write_data; accepted<='1';
                            elsif count(c)<2 then
                                addr_q(c,count(c))<=address; data_q(c,count(c))<=write_data;
                                count(c)<=count(c)+1; accepted<='1';
                            end if;
                        when 1 =>
                            if tso='1' and count(c)=2 and addr_q(c,1)=address then read_data<=data_q(c,1);
                            elsif tso='1' and count(c)/=0 and addr_q(c,0)=address then read_data<=data_q(c,0);
                            else read_data<=memory(a); end if;
                            accepted<='1'; read_valid<='1';
                        when 2 | 3 =>
                            if count(c)/=0 then
                                memory(index_of(addr_q(c,0)))<=data_q(c,0);
                                addr_q(c,0)<=addr_q(c,1); data_q(c,0)<=data_q(c,1); count(c)<=count(c)-1;
                                if cmd=2 then accepted<='1'; end if;
                            else accepted<='1'; end if;
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;
end architecture;
