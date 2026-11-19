library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity alloy_dram_cache is
    generic(PREDICT_ENABLE: boolean := true; TAG_CYCLES: positive := 30; DATA_CYCLES: positive := 4;
            MEMORY_CYCLES: positive := 100; PREDICT_CYCLES: positive := 1);
    port(clk, reset, req_valid: in std_logic; line_address: in unsigned(31 downto 0); predictor_index: in unsigned(1 downto 0);
         req_ready, response_valid, response_hit, predicted_hit: out std_logic;
         response_data, response_latency, hits, misses, correct_hit, correct_miss, false_hit, false_miss, backing_reads: out unsigned(31 downto 0));
end entity;
architecture rtl of alloy_dram_cache is
    type words is array(0 to 3) of unsigned(31 downto 0);
    type counters is array(0 to 3) of unsigned(1 downto 0);
    signal valid_bits: std_logic_vector(3 downto 0) := (others=>'0');
    signal tags, data: words := (others=>(others=>'0'));
    signal prediction: counters := (others=>"01");
    signal remaining: natural := 0;
    function memory_data(address: unsigned(31 downto 0)) return unsigned is
    begin return address xor unsigned'(x"c39a57e1"); end function;
begin
    req_ready <= '1' when remaining=0 else '0';
    process(clk)
        variable idx,pi,chosen_latency: natural;
        variable actual,predicted: boolean;
    begin
        if rising_edge(clk) then
            if reset='1' then
                valid_bits<=(others=>'0'); tags<=(others=>(others=>'0')); data<=(others=>(others=>'0'));
                prediction<=(others=>"01"); remaining<=0; response_valid<='0'; response_hit<='0'; predicted_hit<='0';
                response_data<=(others=>'0'); response_latency<=(others=>'0'); hits<=(others=>'0'); misses<=(others=>'0');
                correct_hit<=(others=>'0'); correct_miss<=(others=>'0'); false_hit<=(others=>'0');
                false_miss<=(others=>'0'); backing_reads<=(others=>'0');
            else
                response_valid<='0';
                if remaining/=0 then
                    remaining<=remaining-1; if remaining=1 then response_valid<='1'; end if;
                elsif req_valid='1' then
                    idx:=to_integer(line_address(1 downto 0)); pi:=to_integer(predictor_index);
                    actual:=valid_bits(idx)='1' and tags(idx)=line_address; predicted:=prediction(pi)(1)='1';
                    if actual then response_hit<='1'; else response_hit<='0'; end if;
                    if predicted then predicted_hit<='1'; else predicted_hit<='0'; end if;
                    if actual then
                        hits<=hits+1; response_data<=data(idx); chosen_latency:=TAG_CYCLES+DATA_CYCLES;
                        if prediction(pi)/=3 then prediction(pi)<=prediction(pi)+1; end if;
                    else
                        misses<=misses+1; response_data<=memory_data(line_address);
                        valid_bits(idx)<='1'; tags(idx)<=line_address; data(idx)<=memory_data(line_address);
                        if PREDICT_ENABLE and not predicted then
                            if PREDICT_CYCLES+MEMORY_CYCLES>TAG_CYCLES then chosen_latency:=PREDICT_CYCLES+MEMORY_CYCLES;
                            else chosen_latency:=TAG_CYCLES; end if;
                        else chosen_latency:=TAG_CYCLES+MEMORY_CYCLES; end if;
                        if prediction(pi)/=0 then prediction(pi)<=prediction(pi)-1; end if;
                    end if;
                    if actual and predicted then correct_hit<=correct_hit+1;
                    elsif not actual and not predicted then correct_miss<=correct_miss+1;
                    elsif not actual and predicted then false_hit<=false_hit+1;
                    else false_miss<=false_miss+1; end if;
                    if not actual or (PREDICT_ENABLE and not predicted) then backing_reads<=backing_reads+1; end if;
                    response_latency<=to_unsigned(chosen_latency,32); remaining<=chosen_latency;
                end if;
            end if;
        end if;
    end process;
end architecture;
