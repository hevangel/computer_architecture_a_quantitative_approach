library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mcs_combining_barrier is
    generic (N : positive := 8; TREE : boolean := true; MCS : boolean := true);
    port (
        clk, reset : in std_logic;
        lock_request, lock_release, barrier_arrive : in std_logic_vector(N-1 downto 0);
        owner, barrier_release : out std_logic_vector(N-1 downto 0);
        handoff_messages, barrier_messages, root_messages : out unsigned(31 downto 0)
    );
end entity;

architecture rtl of mcs_combining_barrier is
    constant LAST : integer := 2*N-2;
    subtype nodes is std_logic_vector(LAST downto 0);
    subtype cores is std_logic_vector(N-1 downto 0);
    type links is array(0 to N-1) of integer range -1 to N-1;
begin
    process(clk)
        variable arrived, released, old_arrived, old_released : nodes;
        variable pending, queued, owner_bits : cores;
        variable successor : links;
        variable tail, holder, delayed_node, delayed_prev : integer range -1 to N-1;
        variable candidate, old_holder, fanout, root_count : integer;
        variable release_wait : boolean;
    begin
        if rising_edge(clk) then
            if reset='1' then
                owner <= (others=>'0'); barrier_release <= (others=>'0');
                handoff_messages <= (others=>'0'); barrier_messages <= (others=>'0'); root_messages <= (others=>'0');
                arrived := (others=>'0'); released := (others=>'0');
                pending := (others=>'0'); queued := (others=>'0');
                tail := -1; holder := -1; delayed_node := -1; delayed_prev := -1;
                successor := (others=>-1);
                release_wait := false;
            else
                old_arrived := arrived; old_released := released;
                for i in 0 to N-1 loop
                    if barrier_arrive(i)='1' and old_arrived(N-1+i)='0' and old_released(0)='0' then
                        arrived(N-1+i) := '1';
                    end if;
                end loop;
                fanout := 0; root_count := 0;
                if TREE then
                    for i in 0 to N-2 loop
                        if old_arrived(i)='0' and old_arrived(2*i+1)='1' and old_arrived(2*i+2)='1' then
                            arrived(i) := '1'; fanout := fanout+2;
                            if i=0 then root_count := root_count+2; end if;
                        end if;
                    end loop;
                    released(0) := old_arrived(0);
                    for i in 1 to LAST loop
                        if old_released(i)='0' and old_released((i-1)/2)='1' then
                            released(i) := '1'; fanout := fanout+1;
                            if i<=2 then root_count := root_count+1; end if;
                        end if;
                    end loop;
                else
                    for i in 0 to N-1 loop
                        if arrived(N-1+i)='1' and old_arrived(N-1+i)='0' then fanout := fanout+1; end if;
                    end loop;
                    if and old_arrived(LAST downto N-1) then
                        released := (others=>'1'); fanout := fanout+N;
                    end if;
                    root_count := fanout;
                end if;
                barrier_messages <= barrier_messages+fanout;
                root_messages <= root_messages+root_count;
                barrier_release <= released(LAST downto N-1);
                if and released(LAST downto N-1) then
                    arrived := (others=>'0'); released := (others=>'0');
                end if;

                old_holder := holder;
                candidate := -1;
                for i in 0 to N-1 loop
                    if lock_request(i)='1' and holder/=i and queued(i)='0' then pending(i) := '1'; end if;
                    if pending(i)='1' and candidate=-1 then candidate := i; end if;
                end loop;
                if MCS then
                    if delayed_prev>=0 then successor(delayed_prev) := delayed_node; end if;
                    delayed_prev := -1; delayed_node := -1;
                    if candidate>=0 then
                        pending(candidate) := '0'; successor(candidate) := -1;
                        if tail<0 then holder := candidate;
                        else delayed_prev := tail; delayed_node := candidate; queued(candidate) := '1'; end if;
                        tail := candidate;
                    end if;
                    if old_holder>=0 then
                        if lock_release(old_holder)='1' or release_wait then
                            release_wait := true;
                            if successor(holder)>=0 then
                                holder := successor(holder); queued(holder) := '0'; release_wait := false;
                                handoff_messages <= handoff_messages+1;
                            elsif tail=holder then
                                holder := -1; tail := -1; release_wait := false;
                            end if;
                        end if;
                    end if;
                else
                    if holder>=0 then
                        if lock_release(holder)='1' then
                            fanout := 0;
                            for i in 0 to N-1 loop
                                if pending(i)='1' then fanout := fanout+1; end if;
                            end loop;
                            handoff_messages <= handoff_messages+fanout;
                            holder := -1;
                        end if;
                    end if;
                    if holder=-1 and candidate>=0 then pending(candidate) := '0'; holder := candidate; end if;
                end if;
                owner_bits := (others=>'0');
                if holder>=0 then owner_bits(holder) := '1'; end if;
                owner <= owner_bits;
            end if;
        end if;
    end process;
end architecture;
