library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity moesi_false_sharing is
    port (
        clk, reset, valid, write : in std_logic;
        core : in unsigned(1 downto 0);
        address : in unsigned(3 downto 0);
        write_word : in unsigned(31 downto 0);
        read_word : out unsigned(31 downto 0);
        miss_kind : out unsigned(2 downto 0);
        memory_writes, peer_dirty_reads, false_misses : out unsigned(31 downto 0);
        requester_state : out unsigned(2 downto 0);
        cache_states : out unsigned(23 downto 0)
    );
end entity;

architecture rtl of moesi_false_sharing is
    constant I : natural := 0; constant S : natural := 1; constant E : natural := 2;
    constant M : natural := 3; constant O : natural := 4;
    type mapping is array(0 to 3,0 to 1) of natural range 0 to 7;
    type lines is array(0 to 3,0 to 1) of unsigned(63 downto 0);
    type memory is array(0 to 7) of unsigned(63 downto 0);
    type shadow is array(0 to 3) of integer range -1 to 7;
    type seen_map is array(0 to 3) of std_logic_vector(7 downto 0);
    type invalidation is array(0 to 3,0 to 7) of std_logic_vector(1 downto 0);
begin
    process(clk)
        variable state, tag : mapping;
        variable data : lines;
        variable backing : memory;
        variable seen : seen_map;
        variable invalid_words : invalidation;
        variable recent, older : shadow;
        variable c, line_num, slot, word_select, category : natural;
        variable matching, shared_copy : boolean;
        variable fill : unsigned(63 downto 0);
    begin
        if rising_edge(clk) then
            if reset='1' then
                memory_writes <= (others=>'0'); peer_dirty_reads <= (others=>'0'); false_misses <= (others=>'0');
                requester_state <= (others=>'0'); read_word <= (others=>'0'); miss_kind <= (others=>'0');
                seen := (others=>(others=>'0')); recent := (others=>-1); older := (others=>-1);
                invalid_words := (others=>(others=>(others=>'0')));
                state := (others=>(others=>I)); tag := (others=>(others=>0));
                data := (others=>(others=>(others=>'0'))); backing := (others=>(others=>'0'));
            elsif valid='1' then
                c := to_integer(core); line_num := to_integer(address(3 downto 1));
                slot := line_num mod 2; word_select := to_integer(address(0 downto 0));
                matching := state(c,slot)/=I and tag(c,slot)=line_num;
                category := 0;
                if not matching then
                    if invalid_words(c,line_num)/="00" then
                        if invalid_words(c,line_num)(word_select)='1' then category := 4;
                        else category := 5; end if;
                    elsif seen(c)(line_num)='0' then category := 1;
                    elsif recent(c)/=line_num and older(c)/=line_num then category := 2;
                    else category := 3; end if;
                    if category=5 then false_misses <= false_misses+1; end if;
                    if state(c,slot)=M or state(c,slot)=O then
                        backing(tag(c,slot)) := data(c,slot);
                        memory_writes <= memory_writes+1;
                    end if;
                    fill := backing(line_num);
                    shared_copy := false;
                    for peer in 0 to 3 loop
                        if peer/=c and state(peer,slot)/=I and tag(peer,slot)=line_num then
                            shared_copy := true;
                            if state(peer,slot)=M or state(peer,slot)=O then
                                fill := data(peer,slot);
                                if write='0' then peer_dirty_reads <= peer_dirty_reads+1; end if;
                                state(peer,slot) := O;
                            elsif state(peer,slot)=E then state(peer,slot) := S; end if;
                        end if;
                    end loop;
                    data(c,slot) := fill; tag(c,slot) := line_num;
                    if shared_copy then state(c,slot) := S; else state(c,slot) := E; end if;
                end if;
                if write='1' then
                    for peer in 0 to 3 loop
                        if peer/=c then
                            if state(peer,slot)/=I and tag(peer,slot)=line_num then
                                state(peer,slot) := I;
                                invalid_words(peer,line_num)(word_select) := '1';
                            elsif invalid_words(peer,line_num)/="00" then
                                invalid_words(peer,line_num)(word_select) := '1';
                            end if;
                        end if;
                    end loop;
                    state(c,slot) := M;
                    data(c,slot)(32*word_select+31 downto 32*word_select) := write_word;
                end if;
                seen(c)(line_num) := '1';
                invalid_words(c,line_num) := "00";
                if recent(c)/=line_num then older(c) := recent(c); recent(c) := line_num; end if;
                miss_kind <= to_unsigned(category,3);
                requester_state <= to_unsigned(state(c,slot),3);
                read_word <= data(c,slot)(32*word_select+31 downto 32*word_select);
            end if;
            for cpu in 0 to 3 loop
                for line_slot in 0 to 1 loop
                    cache_states(6*cpu+3*line_slot+2 downto 6*cpu+3*line_slot) <= to_unsigned(state(cpu,line_slot),3);
                end loop;
            end loop;
        end if;
    end process;
end architecture;
