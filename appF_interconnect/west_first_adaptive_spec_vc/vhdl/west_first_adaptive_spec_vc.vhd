library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity west_first_adaptive_spec_vc is
    generic (SPECULATIVE, ADAPTIVE : boolean := true);
    port (
        clk, reset : in std_logic;
        in_valid, out_ready : in std_logic_vector(15 downto 0);
        in_ready, out_valid : out std_logic_vector(15 downto 0);
        destination, link_enable : in std_logic_vector(63 downto 0);
        in_id : in std_logic_vector(255 downto 0);
        out_id : out std_logic_vector(255 downto 0);
        link_hops, alternate_turns : out unsigned(31 downto 0)
    );
end entity;
architecture rtl of west_first_adaptive_spec_vc is
    constant WEST : integer:=0;
    constant EAST : integer:=1;
    constant NORTH : integer:=2;
    constant SOUTH : integer:=3;
    constant LOCAL : integer:=4;
    type destinations is array(0 to 159) of natural range 0 to 15;
    type packets is array(0 to 159) of std_logic_vector(15 downto 0);
    type links is array(0 to 79) of integer range -1 to 159;
    type locals is array(0 to 15) of integer range -1 to 159;
    type state is record
        occ : std_logic_vector(159 downto 0);
        dst : destinations;
        data : packets;
        held, target : links;
        hold_alt : std_logic_vector(79 downto 0);
        local_held : locals;
        rotation : natural range 0 to 9;
        hops, turns : unsigned(31 downto 0);
    end record;
    constant INITIAL : state := (
        (others=>'0'),(others=>0),(others=>(others=>'0')),
        (others=>-1),(others=>-1),(others=>'0'),(others=>-1),0,(others=>'0'),(others=>'0')
    );
    signal q,d : state := INITIAL;
    function neighbor(node, direction : integer) return integer is
    begin
        case direction is
            when WEST  => if node mod 4/=0 then return node-1; end if;
            when EAST  => if node mod 4/=3 then return node+1; end if;
            when NORTH => if node/4/=0 then return node-4; end if;
            when SOUTH => if node/4/=3 then return node+4; end if;
            when others => null;
        end case;
        return -1;
    end;
    function opposite(direction : integer) return integer is
    begin
        if direction mod 2=0 then return direction+1; else return direction-1; end if;
    end;
begin
    link_hops<=q.hops; alternate_turns<=q.turns;
    process(all)
        variable s : state;
        variable ob : std_logic_vector(79 downto 0);
        variable ib : std_logic_vector(159 downto 0);
        variable index,candidate,want,other,chosen,dx,dy,target_id,free1,free2,vc1,vc2,output_index : integer;
        variable alt : boolean;
        procedure credits(node,dir : in integer; variable free_count, vc_index : out integer) is
            variable peer,slot : integer;
        begin
            free_count:=0; vc_index:=-1;
            peer:=neighbor(node,dir);
            if peer>=0 then
                if link_enable(4*node+dir)='1' and ob(5*node+dir)='0' then
                    for n in 1 downto 0 loop
                        slot:=10*peer+2*opposite(dir)+n;
                        if q.occ(slot)='0' then free_count:=free_count+1; vc_index:=slot; end if;
                    end loop;
                end if;
            end if;
        end;
    begin
        s:=q; s.rotation:=(q.rotation+1) mod 10;
        out_valid<=(others=>'0'); out_id<=(others=>'0'); in_ready<=(others=>'0');
        ob:=(others=>'0'); ib:=(others=>'0');
        for port_id in 0 to 79 loop
            if q.held(port_id)>=0 then
                candidate:=q.held(port_id); target_id:=q.target(port_id);
                ib(candidate):='1'; ib(opposite(candidate)):='1'; ob(port_id):='1';
                if link_enable(4*(port_id/5)+port_id mod 5)='1' and q.occ(target_id)='0' then
                    s.occ(target_id):='1'; s.dst(target_id):=q.dst(candidate); s.data(target_id):=q.data(candidate);
                    s.occ(candidate):='0'; s.held(port_id):=-1; s.hops:=s.hops+1;
                    if q.hold_alt(port_id)='1' then s.turns:=s.turns+1; end if;
                end if;
            end if;
        end loop;
        for node in 0 to 15 loop
            if q.local_held(node)>=0 then
                index:=q.local_held(node); ib(index):='1'; ib(opposite(index)):='1'; ob(5*node+LOCAL):='1';
                out_valid(node)<=not reset; out_id(16*node+15 downto 16*node)<=q.data(index);
                if out_ready(node)='1' then s.occ(index):='0'; s.local_held(node):=-1; end if;
            end if;
            for step in 0 to 9 loop
                candidate:=10*node+(q.rotation+step) mod 10;
                if q.occ(candidate)='1' and ib(candidate)='0' then
                    dx:=q.dst(candidate) mod 4-node mod 4;
                    dy:=q.dst(candidate)/4-node/4;
                    other:=-1;
                    if dx<0 then want:=WEST;
                    elsif dx=0 and dy=0 then want:=LOCAL;
                    elsif dx=0 then
                        if dy<0 then want:=NORTH; else want:=SOUTH; end if;
                    else
                        want:=EAST;
                        if ADAPTIVE and dy/=0 then
                            if dy<0 then other:=NORTH; else other:=SOUTH; end if;
                        end if;
                    end if;
                    if want=LOCAL then
                        if ob(5*node+LOCAL)='0' then
                            out_valid(node)<=not reset; out_id(16*node+15 downto 16*node)<=q.data(candidate);
                            ob(5*node+LOCAL):='1'; ib(opposite(candidate)):='1';
                            if out_ready(node)='1' then s.occ(candidate):='0';
                            else s.local_held(node):=candidate; end if;
                        end if;
                    else
                        credits(node,want,free1,vc1); credits(node,other,free2,vc2);
                        alt:=free2>free1;
                        if alt then chosen:=other; target_id:=vc2; else chosen:=want; target_id:=vc1; end if;
                        if target_id>=0 then
                            output_index:=5*node+chosen; ob(output_index):='1'; ib(opposite(candidate)):='1';
                            if SPECULATIVE then
                                s.occ(target_id):='1'; s.dst(target_id):=q.dst(candidate); s.data(target_id):=q.data(candidate);
                                s.occ(candidate):='0'; s.hops:=s.hops+1;
                                if alt then s.turns:=s.turns+1; end if;
                            else
                                s.held(output_index):=candidate; s.target(output_index):=target_id;
                                if alt then s.hold_alt(output_index):='1'; else s.hold_alt(output_index):='0'; end if;
                            end if;
                        end if;
                    end if;
                end if;
            end loop;
            index:=10*node+8;
            if q.occ(index)='1' then index:=index+1; end if;
            if q.occ(index)='0' and reset='0' then
                in_ready(node)<='1';
                if in_valid(node)='1' then
                    s.occ(index):='1'; s.dst(index):=to_integer(unsigned(destination(4*node+3 downto 4*node)));
                    s.data(index):=in_id(16*node+15 downto 16*node);
                end if;
            end if;
        end loop;
        d<=s;
    end process;
    process(clk)
    begin
        if rising_edge(clk) then
            if reset='1' then q<=INITIAL; else q<=d; end if;
        end if;
    end process;
end architecture;
