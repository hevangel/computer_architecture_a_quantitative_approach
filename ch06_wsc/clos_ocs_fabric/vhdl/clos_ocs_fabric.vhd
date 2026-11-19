library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity clos_ocs_fabric is
    port (
        clk, reset : in std_logic;
        in_valid : in std_logic_vector(31 downto 0);
        in_ready : out std_logic_vector(31 downto 0);
        in_destination : in std_logic_vector(95 downto 0);
        in_id : in std_logic_vector(511 downto 0);
        out_valid : out std_logic_vector(31 downto 0);
        out_ready : in std_logic_vector(7 downto 0);
        out_id : out std_logic_vector(511 downto 0);
        cfg_valid : in std_logic;
        cfg_cross : in std_logic_vector(3 downto 0);
        cfg_ready : out std_logic;
        active_cross : out std_logic_vector(3 downto 0)
    );
end entity;

architecture rtl of clos_ocs_fabric is
    type destinations is array(0 to 31) of natural range 0 to 7;
    type packets is array(0 to 31) of std_logic_vector(15 downto 0);
    signal queued, flight : std_logic_vector(31 downto 0);
    signal flight_id : packets;
    signal changing : std_logic;
    function secondary(leaf : natural; mapping : std_logic_vector(3 downto 0)) return natural is
        variable port_number : natural := leaf mod 2;
    begin
        if mapping(leaf/2)='1' then port_number:=1-port_number; end if;
        return 1+leaf/4+port_number;
    end;
begin
    cfg_ready <= not changing when reset='0' else '0';
    in_ready <= not queued when reset='0' else (others=>'0');
    out_valid <= flight when reset='0' else (others=>'0');
    ports_out: for i in 0 to 31 generate
        out_id(16*i+15 downto 16*i) <= flight_id(i);
    end generate;

    process(clk)
        variable q, f, used_ingress_link : std_logic_vector(31 downto 0);
        variable destination : destinations;
        variable packet, f_ids : packets;
        variable desired, active : std_logic_vector(3 downto 0);
        variable busy : std_logic;
        variable rotation, candidate, src, dest, spine, slot : natural;
    begin
        if rising_edge(clk) then
            if reset='1' then
                q:=(others=>'0'); f:=(others=>'0'); desired:=(others=>'0'); active:=(others=>'0');
                busy:='0'; rotation:=0; destination:=(others=>0);
                packet:=(others=>(others=>'0')); f_ids:=(others=>(others=>'0'));
            else
                for i in 0 to 31 loop
                    if f(i)='1' and out_ready(i/4)='1' then f(i):='0'; end if;
                end loop;
                if cfg_valid='1' and cfg_ready='1' then desired:=cfg_cross; busy:='1'; end if;
                if busy='1' then
                    if unsigned(f)=0 then active:=desired; busy:='0'; end if;
                else
                    used_ingress_link:=(others=>'0');
                    for step in 0 to 31 loop
                        candidate:=(rotation+step) mod 32;
                        src:=candidate/4; dest:=destination(candidate);
                        if q(candidate)='1' then
                            for lane in 0 to 1 loop
                                if lane=0 then spine:=0; else spine:=secondary(src,active); end if;
                                slot:=4*dest+spine;
                                if q(candidate)='1' and used_ingress_link(4*src+spine)='0' and f(slot)='0' and
                                   (spine=0 or spine=secondary(dest,active)) then
                                    used_ingress_link(4*src+spine):='1'; f(slot):='1';
                                    f_ids(slot):=packet(candidate); q(candidate):='0';
                                end if;
                            end loop;
                        end if;
                    end loop;
                end if;
                rotation:=(rotation+1) mod 32;
                for i in 0 to 31 loop
                    if in_valid(i)='1' and in_ready(i)='1' then
                        q(i):='1'; destination(i):=to_integer(unsigned(in_destination(3*i+2 downto 3*i)));
                        packet(i):=in_id(16*i+15 downto 16*i);
                    end if;
                end loop;
            end if;
            queued<=q; flight<=f; flight_id<=f_ids; changing<=busy; active_cross<=active;
        end if;
    end process;
end architecture;
