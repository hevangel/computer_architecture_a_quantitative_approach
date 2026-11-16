library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tournament_btb_ras is
    port(clk, reset: in std_logic; pc: in unsigned(31 downto 0);
         update_valid: in std_logic; update_kind: in unsigned(1 downto 0);
         actual_taken: in std_logic; actual_target: in unsigned(31 downto 0);
         local_taken, global_taken, tournament_taken, btb_hit: out std_logic;
         btb_target: out unsigned(31 downto 0); ras_valid: out std_logic; ras_target: out unsigned(31 downto 0));
end entity;
architecture rtl of tournament_btb_ras is
    type counters is array(natural range <>) of unsigned(1 downto 0);
    type words is array(natural range <>) of unsigned(31 downto 0);
    signal local_history: counters(0 to 3) := (others=>(others=>'0'));
    signal local_table: counters(0 to 15) := (others=>"01");
    signal global_table, selector: counters(0 to 3) := (others=>"01");
    signal global_history: unsigned(1 downto 0) := (others=>'0');
    signal btb_valid: std_logic_vector(3 downto 0) := (others=>'0');
    signal btb_tag, btb_value, stack: words(0 to 3) := (others=>(others=>'0'));
    signal stack_count: natural range 0 to 4 := 0;
    signal idx: natural range 0 to 3;
    signal local_index: natural range 0 to 15;
    signal local_p, global_p, btb_match: std_logic;
    function update_counter(value: unsigned(1 downto 0); taken: std_logic) return unsigned is
    begin
        if taken='1' and value<3 then return value+1;
        elsif taken='0' and value>0 then return value-1;
        else return value; end if;
    end function;
begin
    idx <= to_integer(pc(3 downto 2));
    local_index <= idx*4 + to_integer(local_history(idx));
    local_p <= local_table(local_index)(1); global_p <= global_table(to_integer(global_history))(1);
    local_taken <= local_p; global_taken <= global_p;
    tournament_taken <= global_p when selector(idx)(1)='1' else local_p;
    btb_match <= '1' when btb_valid(idx)='1' and btb_tag(idx)=pc else '0';
    btb_hit <= btb_match; btb_target <= btb_value(idx) when btb_match='1' else (others=>'0');
    ras_valid <= '1' when stack_count/=0 else '0';
    ras_target <= stack(stack_count-1) when stack_count/=0 else (others=>'0');
    process(clk)
        variable global_is_correct: std_logic;
    begin
        if rising_edge(clk) then
            if reset='1' then
                local_history <= (others=>(others=>'0')); global_history <= (others=>'0');
                local_table <= (others=>"01"); global_table <= (others=>"01"); selector <= (others=>"01");
                btb_valid <= (others=>'0'); btb_tag <= (others=>(others=>'0'));
                btb_value <= (others=>(others=>'0')); stack <= (others=>(others=>'0')); stack_count <= 0;
            elsif update_valid='1' then
                if update_kind=0 then
                    local_table(local_index) <= update_counter(local_table(local_index),actual_taken);
                    global_table(to_integer(global_history)) <= update_counter(global_table(to_integer(global_history)),actual_taken);
                    if local_p/=global_p then
                        if global_p=actual_taken then global_is_correct:='1'; else global_is_correct:='0'; end if;
                        selector(idx) <= update_counter(selector(idx),global_is_correct);
                    end if;
                    local_history(idx) <= local_history(idx)(0) & actual_taken;
                    global_history <= global_history(0) & actual_taken;
                end if;
                if (update_kind=0 and actual_taken='1') or update_kind=1 then
                    btb_valid(idx)<='1'; btb_tag(idx)<=pc; btb_value(idx)<=actual_target;
                end if;
                if update_kind=1 then
                    if stack_count<4 then stack(stack_count)<=pc+4; stack_count<=stack_count+1;
                    else stack(0)<=stack(1); stack(1)<=stack(2); stack(2)<=stack(3); stack(3)<=pc+4; end if;
                elsif update_kind=2 and stack_count/=0 then stack_count<=stack_count-1;
                end if;
            end if;
        end if;
    end process;
end architecture;
