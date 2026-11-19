library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity split_bus_transient_msi is
    generic (DATA_DELAY : natural := 2);
    port (
        clk, reset, allow_data : in std_logic;
        req_valid : in std_logic_vector(1 downto 0);
        req_op : in std_logic_vector(3 downto 0);
        req_data : in std_logic_vector(63 downto 0);
        req_ready, rsp_valid : out std_logic_vector(1 downto 0);
        rsp_data : out std_logic_vector(63 downto 0);
        cache_state : out std_logic_vector(7 downto 0);
        memory_word, upgrade_races : out unsigned(31 downto 0)
    );
end entity;

architecture rtl of split_bus_transient_msi is
    constant I : natural := 0; constant S : natural := 1; constant M : natural := 2;
    constant IM_AD : natural := 3; constant IM_D : natural := 4; constant SM_AD : natural := 5;
    constant MI_A : natural := 6; constant IS_D : natural := 7;
    type states is array(0 to 1) of natural range 0 to 7;
    type ops is array(0 to 1) of natural range 0 to 3;
    type words is array(0 to 1) of std_logic_vector(31 downto 0);
    signal pending_q : std_logic_vector(1 downto 0);
begin
    req_ready <= not pending_q when reset='0' else "00";
    process(clk)
        variable state : states;
        variable operation : ops;
        variable cache, write_data : words;
        variable pending, accept : std_logic_vector(1 downto 0);
        variable active : boolean;
        variable bus_core, priority_core : natural range 0 to 1;
        variable response_delay : natural range 0 to DATA_DELAY;
        variable bus_data, backing : std_logic_vector(31 downto 0);
        variable races : unsigned(31 downto 0);
        variable selected, peer : integer range -1 to 1;
    begin
        if rising_edge(clk) then
            rsp_valid <= "00";
            if reset='1' then
                pending := "00"; active := false; priority_core := 0;
                state := (others=>I); operation := (others=>0);
                cache := (others=>(others=>'0')); write_data := (others=>(others=>'0'));
                backing := (others=>'0'); races := (others=>'0');
                rsp_data <= (others=>'0');
            else
                accept := req_valid and not pending;
                if active then
                    if response_delay>0 then response_delay := response_delay-1;
                    elsif allow_data='1' then
                        case state(bus_core) is
                            when IM_D =>
                                state(bus_core) := M; cache(bus_core) := write_data(bus_core);
                                rsp_data(32*bus_core+31 downto 32*bus_core) <= write_data(bus_core);
                            when IS_D =>
                                state(bus_core) := S; cache(bus_core) := bus_data;
                                rsp_data(32*bus_core+31 downto 32*bus_core) <= bus_data;
                            when MI_A => state(bus_core) := I; backing := bus_data;
                            when others => null;
                        end case;
                        rsp_valid(bus_core) <= '1';
                        pending(bus_core) := '0'; active := false;
                    end if;
                else
                    selected := -1;
                    if pending(priority_core)='1' then selected := priority_core;
                    elsif pending(1-priority_core)='1' then selected := 1-priority_core; end if;
                    if selected>=0 then
                        peer := 1-selected; priority_core := peer;
                        if (operation(selected)=0 and state(selected)/=I) or
                           (operation(selected)=1 and state(selected)=M) or
                           (operation(selected)=2 and state(selected)/=MI_A) then
                            case operation(selected) is
                                when 0 => rsp_data(32*selected+31 downto 32*selected) <= cache(selected);
                                when 1 =>
                                    cache(selected) := write_data(selected);
                                    rsp_data(32*selected+31 downto 32*selected) <= write_data(selected);
                                when 2 => state(selected) := I;
                                when others => null;
                            end case;
                            rsp_valid(selected) <= '1'; pending(selected) := '0';
                        else
                            bus_core := selected; active := true; response_delay := DATA_DELAY;
                            bus_data := backing;
                            case operation(selected) is
                                when 0 =>
                                    if state(peer)=M or state(peer)=MI_A then
                                        bus_data := cache(peer); backing := bus_data; state(peer) := S;
                                    end if;
                                    state(selected) := IS_D;
                                when 1 =>
                                    if state(peer)=M or state(peer)=MI_A then
                                        bus_data := cache(peer); backing := bus_data;
                                    end if;
                                    if state(peer)=SM_AD then
                                        state(peer) := IM_AD; races := races+1;
                                    elsif state(peer)/=IM_AD then state(peer) := I; end if;
                                    state(selected) := IM_D;
                                when 2 => bus_data := cache(selected);
                                when others => null;
                            end case;
                        end if;
                    end if;
                end if;
                for core in 0 to 1 loop
                    if accept(core)='1' then
                        pending(core) := '1';
                        operation(core) := to_integer(unsigned(req_op(2*core+1 downto 2*core)));
                        write_data(core) := req_data(32*core+31 downto 32*core);
                        if operation(core)=1 then
                            if state(core)=I then state(core) := IM_AD;
                            elsif state(core)=S then state(core) := SM_AD; end if;
                        elsif operation(core)=2 and state(core)=M then state(core) := MI_A; end if;
                    end if;
                end loop;
            end if;
            pending_q <= pending;
            cache_state <= std_logic_vector(to_unsigned(state(1),4) & to_unsigned(state(0),4));
            memory_word <= unsigned(backing);
            upgrade_races <= races;
        end if;
    end process;
end architecture;
