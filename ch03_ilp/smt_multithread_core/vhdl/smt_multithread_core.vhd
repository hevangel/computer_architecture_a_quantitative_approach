library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Work-in-progress counterpart to the SystemVerilog scheduling prototype.
entity smt_multithread_core is
    generic (MODE : integer := 3; NPHYS : integer := 20; ROB_SIZE : integer := 8;
             PROGRAM_SIZE : integer := 64; LOAD_LATENCY : integer := 7; MUL_LATENCY : integer := 4);
    port (clk, reset, prog_we, prog_thread : in std_logic;
          prog_op : in unsigned(1 downto 0); prog_dst, prog_src : in unsigned(2 downto 0);
          prog_arg : in unsigned(31 downto 0); mem_we : in std_logic;
          mem_addr : in unsigned(7 downto 0); mem_data : in unsigned(31 downto 0);
          start, read_thread : in std_logic; read_reg : in unsigned(2 downto 0);
          read_value : out unsigned(31 downto 0); prog_ready, done : out std_logic;
          cycles, issued, switches : out integer);
end entity;

architecture behavioral of smt_multithread_core is
    type word_program is array(0 to 1, 0 to PROGRAM_SIZE-1) of unsigned(31 downto 0);
    type int_program is array(0 to 1, 0 to PROGRAM_SIZE-1) of integer;
    type word_memory is array(0 to 255) of unsigned(31 downto 0);
    type word_prf is array(0 to 1, 0 to NPHYS-1) of unsigned(31 downto 0);
    type bool_prf is array(0 to 1, 0 to NPHYS-1) of boolean;
    type int_maps is array(0 to 1, 0 to 7) of integer;
    type int_pair is array(0 to 1) of integer;
    type int_rob is array(0 to 1, 0 to ROB_SIZE-1) of integer;
    type word_rob is array(0 to 1, 0 to ROB_SIZE-1) of unsigned(31 downto 0);
    type bool_rob is array(0 to 1, 0 to ROB_SIZE-1) of boolean;
    signal load_enabled : std_logic := '0';
    signal length0, length1 : integer := 0;
    function bit_index(b : std_logic) return integer is
    begin if b='1' then return 1; else return 0; end if; end function;
begin
    prog_ready <= '1' when reset='0' and load_enabled='1' and
                  ((prog_thread='0' and length0<PROGRAM_SIZE) or (prog_thread='1' and length1<PROGRAM_SIZE)) else '0';
    process(clk)
        variable program_op, program_dst, program_src : int_program;
        variable program_arg : word_program;
        variable memory : word_memory;
        variable plen, pc, head, count : int_pair := (others => 0);
        variable prf : word_prf;
        variable ready, free_phys : bool_prf;
        variable front, committed : int_maps;
        variable rob_op, rob_src, rob_dst, rob_old, rob_arch, rob_due : int_rob;
        variable rob_arg, rob_value : word_rob;
        variable rob_issued, rob_done : bool_rob;
        variable active, rr, cycle_v, issued_v, switches_v : integer := 0;
        variable running, done_v : boolean := false;
        variable idx, tail, dest, arch, src_tag, old_tag, chosen, candidate_idx : integer;
        variable mem_available, switching : boolean;
        variable operand, value, address : unsigned(31 downto 0);
        impure function candidate(thread_id : integer; mem_ok : boolean) return integer is
            variable pos, result : integer := -1;
        begin
            for n in 0 to count(thread_id)-1 loop
                pos := (head(thread_id)+n) mod ROB_SIZE;
                if not rob_issued(thread_id,pos) then
                    if ready(thread_id,rob_src(thread_id,pos)) and (mem_ok or rob_op(thread_id,pos)/=2) then result := pos; end if;
                    exit;
                end if;
            end loop;
            return result;
        end function;
        impure function thread_done(thread_id : integer) return boolean is
        begin return pc(thread_id)=plen(thread_id) and count(thread_id)=0; end function;
    begin
        if rising_edge(clk) then
            if reset='1' then
                running:=false; done_v:=false; cycle_v:=0; issued_v:=0; switches_v:=0; active:=0; rr:=0;
                for t in 0 to 1 loop
                    plen(t):=0; pc(t):=0; head(t):=0; count(t):=0;
                    for p in 0 to NPHYS-1 loop
                        prf(t,p):=(others=>'0'); ready(t,p):=true; free_phys(t,p):=(p>=8);
                    end loop;
                    for p in 0 to 7 loop front(t,p):=p; committed(t,p):=p; end loop;
                    for p in 0 to ROB_SIZE-1 loop rob_issued(t,p):=false; rob_done(t,p):=false; end loop;
                end loop;
                for p in 0 to 255 loop memory(p):=(others=>'0'); end loop;
            elsif not running and not done_v then
                if prog_we='1' and prog_ready='1' then
                    idx:=bit_index(prog_thread); tail:=plen(idx);
                    program_op(idx,tail):=to_integer(prog_op); program_dst(idx,tail):=to_integer(prog_dst);
                    program_src(idx,tail):=to_integer(prog_src); program_arg(idx,tail):=prog_arg;
                    plen(idx):=plen(idx)+1;
                end if;
                if mem_we='1' then memory(to_integer(mem_addr)):=mem_data; end if;
                if start='1' then running:=true; end if;
            elsif running then
                for t in 0 to 1 loop
                    for k in 0 to count(t)-1 loop
                        idx:=(head(t)+k) mod ROB_SIZE;
                        if rob_issued(t,idx) and not rob_done(t,idx) and rob_due(t,idx)=cycle_v then
                            prf(t,rob_dst(t,idx)):=rob_value(t,idx); ready(t,rob_dst(t,idx)):=true; rob_done(t,idx):=true;
                        end if;
                    end loop;
                    for slot in 0 to 1 loop
                        if count(t)>0 then
                            if rob_done(t,head(t)) then
                                idx:=head(t); committed(t,rob_arch(t,idx)):=rob_dst(t,idx); free_phys(t,rob_old(t,idx)):=true;
                                head(t):=(head(t)+1) mod ROB_SIZE; count(t):=count(t)-1;
                            end if;
                        end if;
                    end loop;
                    for slot in 0 to 1 loop
                        dest:=-1;
                        for p in 0 to NPHYS-1 loop if free_phys(t,p) and dest=-1 then dest:=p; end if; end loop;
                        if pc(t)<plen(t) and count(t)<ROB_SIZE and dest>=0 then
                            tail:=(head(t)+count(t)) mod ROB_SIZE; arch:=program_dst(t,pc(t));
                            src_tag:=front(t,program_src(t,pc(t))); old_tag:=front(t,arch);
                            free_phys(t,dest):=false; ready(t,dest):=false; front(t,arch):=dest;
                            rob_op(t,tail):=program_op(t,pc(t)); rob_src(t,tail):=src_tag; rob_dst(t,tail):=dest;
                            rob_old(t,tail):=old_tag; rob_arch(t,tail):=arch; rob_arg(t,tail):=program_arg(t,pc(t));
                            rob_issued(t,tail):=false; rob_done(t,tail):=false; pc(t):=pc(t)+1; count(t):=count(t)+1;
                        end if;
                    end loop;
                end loop;
                if MODE=0 and thread_done(0) then active:=1; end if;
                switching:=false;
                if MODE=1 and candidate(active,true)=-1 and not thread_done(1-active) and candidate(1-active,true)/=-1 then
                    active:=1-active; switches_v:=switches_v+1; switching:=true;
                end if;
                if not switching then
                    if MODE=2 then chosen:=cycle_v mod 2; elsif MODE=3 then chosen:=rr; else chosen:=active; end if;
                    mem_available:=true;
                    for slot in 0 to 1 loop
                        candidate_idx:=candidate(chosen,mem_available);
                        if MODE=3 and candidate_idx=-1 then chosen:=1-chosen; candidate_idx:=candidate(chosen,mem_available); end if;
                        if candidate_idx>=0 then
                            operand:=prf(chosen,rob_src(chosen,candidate_idx));
                            case rob_op(chosen,candidate_idx) is
                                when 0 => value:=operand+rob_arg(chosen,candidate_idx); rob_due(chosen,candidate_idx):=cycle_v+1;
                                when 1 => value:=resize(operand*rob_arg(chosen,candidate_idx),32); rob_due(chosen,candidate_idx):=cycle_v+MUL_LATENCY;
                                when others => address:=operand+rob_arg(chosen,candidate_idx); value:=memory(to_integer(address(7 downto 0)));
                                    rob_due(chosen,candidate_idx):=cycle_v+LOAD_LATENCY; mem_available:=false;
                            end case;
                            rob_value(chosen,candidate_idx):=value; rob_issued(chosen,candidate_idx):=true; issued_v:=issued_v+1;
                            if MODE=3 then chosen:=1-chosen; end if;
                        end if;
                    end loop;
                    if MODE=3 then rr:=1-rr; end if;
                end if;
                cycle_v:=cycle_v+1;
                if thread_done(0) and thread_done(1) then running:=false; done_v:=true; end if;
            end if;
            length0<=plen(0); length1<=plen(1);
            if not running and not done_v then load_enabled<='1'; else load_enabled<='0'; end if;
            if done_v then done<='1'; else done<='0'; end if;
            cycles<=cycle_v; issued<=issued_v; switches<=switches_v;
            read_value<=prf(bit_index(read_thread),committed(bit_index(read_thread),to_integer(read_reg)));
        end if;
    end process;
end architecture;
