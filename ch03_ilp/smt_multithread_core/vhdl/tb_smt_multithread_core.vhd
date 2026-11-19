library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity tb_smt_multithread_core is end;
architecture test of tb_smt_multithread_core is
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal prog_we, prog_thread, mem_we, start, read_thread : std_logic := '0';
    signal prog_op : unsigned(1 downto 0) := (others=>'0');
    signal prog_dst, prog_src, read_reg : unsigned(2 downto 0) := (others=>'0');
    signal prog_arg, mem_data : unsigned(31 downto 0) := (others=>'0');
    signal mem_addr : unsigned(7 downto 0) := (others=>'0');
    type words is array (0 to 4) of unsigned(31 downto 0);
    type ints is array (0 to 4) of integer;
    signal read_value : words;
    signal prog_ready : std_logic_vector(0 to 4);
    signal done : std_logic_vector(0 to 4);
    signal cycles, issued, switches : ints;
    function to_bit(n : integer) return std_logic is
    begin if n=0 then return '0'; else return '1'; end if; end function;
begin
    clk <= not clk after 5 ns;
    modes: for m in 0 to 4 generate
        function mode_value return integer is
        begin if m=4 then return 3; else return m; end if; end function;
        function phys_value return integer is
        begin if m=4 then return 9; else return 20; end if; end function;
    begin
        dut: entity work.smt_multithread_core generic map(MODE=>mode_value, NPHYS=>phys_value)
            port map(clk=>clk, reset=>reset, prog_we=>prog_we, prog_thread=>prog_thread,
                prog_op=>prog_op, prog_dst=>prog_dst, prog_src=>prog_src, prog_arg=>prog_arg,
                mem_we=>mem_we, mem_addr=>mem_addr, mem_data=>mem_data, start=>start,
                read_thread=>read_thread, read_reg=>read_reg, read_value=>read_value(m),
                prog_ready=>prog_ready(m), done=>done(m), cycles=>cycles(m), issued=>issued(m), switches=>switches(m));
    end generate;
    process
        procedure add_instruction(thread_id, op, dst, src, arg : integer) is
        begin
            wait until falling_edge(clk);
            prog_we<='1'; prog_thread<=to_bit(thread_id); prog_op<=to_unsigned(op,2);
            prog_dst<=to_unsigned(dst,3); prog_src<=to_unsigned(src,3); prog_arg<=to_unsigned(arg,32);
        end procedure;
        variable timeout : integer := 0;
        variable expected : integer;
        type golden_array is array(0 to 1,0 to 7) of unsigned(31 downto 0);
        variable golden : golden_array;
        variable random_state : unsigned(31 downto 0);
        variable src_rand, dst_rand, arg_rand, op_rand : integer;
    begin
        wait until falling_edge(clk); wait until falling_edge(clk); reset<='0';
        mem_we<='1'; mem_addr<=to_unsigned(0,8); mem_data<=to_unsigned(11,32);
        wait until falling_edge(clk); mem_addr<=to_unsigned(1,8); mem_data<=to_unsigned(17,32);
        wait until falling_edge(clk); mem_we<='0';
        for t in 0 to 1 loop
            add_instruction(t,0,6,6,1);
            for k in 0 to 4 loop
                add_instruction(t,2,1,0,(k+t) mod 2);
                for j in 0 to 3 loop add_instruction(t,0,2+j,2+j,1); end loop;
                add_instruction(t,0,7,1,1); add_instruction(t,1,6,6,2);
            end loop;
        end loop;
        wait until falling_edge(clk); prog_we<='0'; start<='1';
        wait until falling_edge(clk); start<='0';
        while done/="11111" and timeout<200 loop
            wait until falling_edge(clk); timeout:=timeout+1;
        end loop;
        assert timeout<200 report "timeout" severity failure;
        report "cycles " & integer'image(cycles(0)) & " " & integer'image(cycles(1)) & " " & integer'image(cycles(2)) & " " & integer'image(cycles(3));
        assert cycles(0)=87 and cycles(1)=57 and cycles(2)=54 and cycles(3)=48 and cycles(4)=83 report "cycle mismatch" severity failure;
        for i in 0 to 4 loop assert issued(i)=72 report "issue count" severity failure; end loop;
        for t in 0 to 1 loop
            read_thread<=to_bit(t);
            for j in 0 to 7 loop
                read_reg<=to_unsigned(j,3); wait until rising_edge(clk); wait for 1 ns;
                case j is
                    when 0 => expected:=0;
                    when 1 => if t=0 then expected:=11; else expected:=17; end if;
                    when 2|3|4|5 => expected:=5;
                    when 6 => expected:=32;
                    when others => if t=0 then expected:=12; else expected:=18; end if;
                end case;
                for i in 0 to 4 loop assert read_value(i)=to_unsigned(expected,32) report "register mismatch" severity failure; end loop;
            end loop;
        end loop;
        wait until falling_edge(clk); reset<='1';
        wait until falling_edge(clk); wait until falling_edge(clk); reset<='0';
        for j in 0 to 63 loop add_instruction(0,0,1,1,1); end loop;
        wait until falling_edge(clk); prog_we<='1'; prog_thread<='0'; prog_arg<=to_unsigned(100,32); wait for 1 ns;
        assert prog_ready="00000" report "full queue accepted write" severity failure;
        wait until falling_edge(clk); prog_thread<='1'; prog_arg<=to_unsigned(7,32); wait for 1 ns;
        assert prog_ready="11111" report "other queue unavailable" severity failure;
        wait until falling_edge(clk); prog_we<='0'; start<='1';
        wait until falling_edge(clk); start<='0'; wait for 1 ns;
        assert prog_ready="00000" report "write enabled during execution" severity failure;
        timeout:=0;
        while done/="11111" and timeout<300 loop
            wait until falling_edge(clk); timeout:=timeout+1;
        end loop;
        assert timeout<300 report "pressure timeout" severity failure;
        for i in 0 to 4 loop assert issued(i)=65 report "pressure issue count" severity failure; end loop;
        read_thread<='0'; read_reg<=to_unsigned(1,3); wait until rising_edge(clk); wait for 1 ns;
        for i in 0 to 4 loop assert read_value(i)=to_unsigned(64,32) report "pressure thread 0" severity failure; end loop;
        read_thread<='1'; wait until rising_edge(clk); wait for 1 ns;
        for i in 0 to 4 loop assert read_value(i)=to_unsigned(7,32) report "pressure thread 1" severity failure; end loop;
        wait until falling_edge(clk); reset<='1';
        wait until falling_edge(clk); wait until falling_edge(clk); reset<='0';
        mem_we<='1'; mem_addr<=to_unsigned(0,8); mem_data<=to_unsigned(11,32);
        wait until falling_edge(clk); mem_addr<=to_unsigned(1,8); mem_data<=to_unsigned(17,32);
        wait until falling_edge(clk); mem_we<='0';
        add_instruction(0,2,1,0,0); add_instruction(0,1,2,1,3);
        add_instruction(0,0,2,0,5); add_instruction(0,0,3,2,1);
        add_instruction(1,2,1,0,1); add_instruction(1,0,2,1,3);
        wait until falling_edge(clk); prog_we<='0'; start<='1';
        wait until falling_edge(clk); start<='0';
        wait until falling_edge(clk);
        assert issued(3)=1 and issued(4)=1 report "two simultaneous loads started" severity failure;
        timeout:=0;
        while done/="11111" and timeout<100 loop
            wait until falling_edge(clk); timeout:=timeout+1;
        end loop;
        assert timeout<100 report "dependency timeout" severity failure;
        assert cycles(0)=21 and cycles(1)=14 and cycles(2)=14 and cycles(3)=13 and cycles(4)=14 report "dependency timing" severity failure;
        read_thread<='0'; read_reg<=to_unsigned(2,3); wait until rising_edge(clk); wait for 1 ns;
        for i in 0 to 4 loop assert read_value(i)=to_unsigned(5,32) report "WAW retirement" severity failure; end loop;
        read_reg<=to_unsigned(3,3); wait until rising_edge(clk); wait for 1 ns;
        for i in 0 to 4 loop assert read_value(i)=to_unsigned(6,32) report "renamed source" severity failure; end loop;
        read_thread<='1'; read_reg<=to_unsigned(2,3); wait until rising_edge(clk); wait for 1 ns;
        for i in 0 to 4 loop assert read_value(i)=to_unsigned(20,32) report "load dependency" severity failure; end loop;
        wait until falling_edge(clk); reset<='1';
        wait until falling_edge(clk); wait until falling_edge(clk); reset<='0';
        random_state:=x"12345678";
        for t in 0 to 1 loop for j in 0 to 7 loop golden(t,j):=(others=>'0'); end loop; end loop;
        for t in 0 to 1 loop
            for k in 0 to 63 loop
                random_state:=resize(random_state*to_unsigned(1664525,32)+to_unsigned(1013904223,64),32);
                src_rand:=to_integer(random_state(10 downto 8)); dst_rand:=to_integer(random_state(14 downto 12));
                arg_rand:=to_integer(random_state(17 downto 16))+1; op_rand:=to_integer(random_state(20 downto 20));
                if op_rand=0 then golden(t,dst_rand):=golden(t,src_rand)+to_unsigned(arg_rand,32);
                else golden(t,dst_rand):=resize(golden(t,src_rand)*to_unsigned(arg_rand,32),32); end if;
                add_instruction(t,op_rand,dst_rand,src_rand,arg_rand);
            end loop;
        end loop;
        wait until falling_edge(clk); prog_we<='0'; start<='1';
        wait until falling_edge(clk); start<='0'; timeout:=0;
        while done/="11111" and timeout<1000 loop
            wait until falling_edge(clk); timeout:=timeout+1;
        end loop;
        assert timeout<1000 report "random timeout" severity failure;
        for i in 0 to 4 loop assert issued(i)=128 report "random issue count" severity failure; end loop;
        for t in 0 to 1 loop
            read_thread<=to_bit(t);
            for j in 0 to 7 loop
                read_reg<=to_unsigned(j,3); wait until rising_edge(clk); wait for 1 ns;
                for i in 0 to 4 loop assert read_value(i)=golden(t,j) report "random register" severity failure; end loop;
            end loop;
        end loop;
        report "TEST PASSED"; finish;
    end process;
end architecture;
