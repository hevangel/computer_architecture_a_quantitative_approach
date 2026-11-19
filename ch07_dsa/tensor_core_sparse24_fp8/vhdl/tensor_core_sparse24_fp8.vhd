library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tensor_core_sparse24_fp8 is
    port (
        clk, reset, start, sparse : in std_logic;
        format : in unsigned(1 downto 0);
        scale_a, scale_b : in signed(7 downto 0);
        a_tile : in unsigned(255 downto 0);
        c_tile : in unsigned(511 downto 0);
        indices : in unsigned(15 downto 0);
        weight_read : out std_logic;
        weight_slot : out unsigned(1 downto 0);
        weights : in unsigned(63 downto 0);
        busy, done, error : out std_logic;
        compute_cycles : out unsigned(2 downto 0);
        weight_reads, flags : out unsigned(4 downto 0);
        d_tile : out unsigned(511 downto 0)
    );
end entity;
architecture rtl of tensor_core_sparse24_fp8 is
    signal sparse_q : std_logic := '0';
    signal slot, format_q : unsigned(1 downto 0) := (others=>'0');
    signal sa, sb : signed(7 downto 0);
    signal a_q : unsigned(255 downto 0);
    signal map_q : unsigned(15 downto 0) := (others=>'0');
    signal next_d : unsigned(511 downto 0);
    signal lane_flags : unsigned(79 downto 0);
begin
    weight_read <= busy;
    weight_slot <= slot;
    columns: for col in 0 to 3 generate
        signal k : natural range 0 to 3;
    begin
        k <= to_integer(map_q(4*col+2*to_integer(slot)+1 downto 4*col+2*to_integer(slot)))
             when sparse_q='1' else to_integer(slot);
        lanes: for row in 0 to 3 generate
            constant L : natural := 4*row+col;
            signal a_operand : unsigned(31 downto 0);
        begin
            a_operand <= resize(a_q(16*(4*row+k)+15 downto 16*(4*row+k)),32);
            fma: entity work.ieee754_fpu_fma_bf16
                port map ("10",format_q,"00",a_operand,resize(weights(16*col+15 downto 16*col),32),
                          d_tile(32*L+31 downto 32*L),sa,sb,
                          next_d(32*L+31 downto 32*L),lane_flags(5*L+4 downto 5*L));
        end generate;
    end generate;
    process(clk)
        variable invalid : boolean;
        variable new_flags : unsigned(4 downto 0);
    begin
        if rising_edge(clk) then
            if reset='1' then
                busy<='0'; done<='0'; error<='0'; compute_cycles<=(others=>'0'); weight_reads<=(others=>'0');
                flags<=(others=>'0'); d_tile<=(others=>'0'); sparse_q<='0';
                slot<=(others=>'0'); format_q<=(others=>'0'); sa<=(others=>'0'); sb<=(others=>'0');
                a_q<=(others=>'0'); map_q<=(others=>'0');
            else
                done<='0';
                if busy='1' then
                    new_flags:=flags;
                    for i in 0 to 15 loop new_flags:=new_flags or lane_flags(5*i+4 downto 5*i); end loop;
                    flags<=new_flags; d_tile<=next_d;
                    compute_cycles<=compute_cycles+1; weight_reads<=weight_reads+4;
                    if (sparse_q='1' and slot=1) or (sparse_q='0' and slot=3) then
                        busy<='0'; done<='1';
                    else slot<=slot+1; end if;
                elsif start='1' then
                    invalid:=format=0;
                    if sparse='1' then
                        for col in 0 to 3 loop
                            if indices(4*col+1 downto 4*col)>=indices(4*col+3 downto 4*col+2) then invalid:=true; end if;
                        end loop;
                    end if;
                    d_tile<=c_tile; compute_cycles<=(others=>'0'); weight_reads<=(others=>'0');
                    flags<=(others=>'0'); slot<=(others=>'0');
                    if invalid then error<='1'; done<='1';
                    else
                        error<='0'; busy<='1'; sparse_q<=sparse; format_q<=format;
                        a_q<=a_tile; map_q<=indices; sa<=scale_a; sb<=scale_b;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
