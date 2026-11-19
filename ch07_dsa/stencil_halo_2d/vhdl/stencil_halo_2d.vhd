library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity stencil_halo_2d is
  port(clk,reset,load_valid : in std_logic; load_addr : in unsigned(5 downto 0); load_data : in unsigned(7 downto 0);
       start,wrap_edges : in std_logic; filter_mode,shift_direction : in unsigned(1 downto 0);
       busy,out_valid : out std_logic; out_ready : in std_logic;
       out_tile : out unsigned(1 downto 0); out_values : out std_logic_vector(255 downto 0);
       load_count : out unsigned(6 downto 0); scratch_read_count : out unsigned(7 downto 0));
end entity;
architecture rtl of stencil_halo_2d is
  type memory_type is array(0 to 63) of unsigned(7 downto 0);
  signal mem : memory_type := (others=>(others=>'0'));
  type line_type is array(0 to 5,0 to 5) of unsigned(7 downto 0);
  signal lines : line_type := (others=>(others=>(others=>'0')));
  signal tile,mode,shift_latched : unsigned(1 downto 0):=(others=>'0');
  signal wrap_latched,active,loading : std_logic:='0';
  signal fill_index : natural range 0 to 35:=0;
  signal scratch_reads : unsigned(7 downto 0):=(others=>'0');
  signal loads : unsigned(6 downto 0):=(others=>'0');
  function sample_pixel(m : memory_type; y,x : integer; wrap_mode : std_logic) return integer is
    variable yy,xx : integer;
  begin
    yy:=y; xx:=x;
    if wrap_mode='1' then
      if yy<0 then yy:=yy+8; elsif yy>7 then yy:=yy-8; end if;
      if xx<0 then xx:=xx+8; elsif xx>7 then xx:=xx-8; end if;
    else
      if yy<0 then yy:=0; elsif yy>7 then yy:=7; end if;
      if xx<0 then xx:=0; elsif xx>7 then xx:=7; end if;
    end if;
    return to_integer(m(yy*8+xx));
  end;
begin
  busy<=active; out_valid<=active and not loading; out_tile<=tile; load_count<=loads; scratch_read_count<=scratch_reads;
  -- The six buffered rows provide tile centers and halo edges. Each lane's
  -- N/S/E/W wires select adjacent buffered values; diagonals shift N/S rows.
  process(all)
    variable n,south,east,west,center,nw,ne,sw,se,value : integer;
    variable result : std_logic_vector(255 downto 0);
  begin
    result:=(others=>'0');
    for row in 0 to 3 loop
      for col in 0 to 3 loop
        center:=to_integer(lines(row+1,col+1));
        n:=to_integer(lines(row,col+1)); south:=to_integer(lines(row+2,col+1));
        west:=to_integer(lines(row+1,col)); east:=to_integer(lines(row+1,col+2));
        nw:=to_integer(lines(row,col)); ne:=to_integer(lines(row,col+2));
        sw:=to_integer(lines(row+2,col)); se:=to_integer(lines(row+2,col+2));
        case mode is
          when "00"=>value:=(ne+2*east+se)-(nw+2*west+sw);
          when "01"=>value:=(sw+2*south+se)-(nw+2*n+ne);
          when "10"=>value:=nw+n+ne+west+center+east+sw+south+se;
          when others=>case shift_latched is
            when "00"=>value:=n; when "01"=>value:=south; when "10"=>value:=east; when others=>value:=west;
          end case;
        end case;
        result((row*4+col)*16+15 downto (row*4+col)*16):=std_logic_vector(to_signed(value,16));
      end loop;
    end loop;
    out_values<=result;
  end process;
  process(clk)
    variable row,col : integer;
  begin
    if rising_edge(clk) then
      if reset='1' then
        active<='0'; loading<='0'; tile<=(others=>'0'); mode<=(others=>'0'); shift_latched<=(others=>'0');
        wrap_latched<='0'; loads<=(others=>'0'); scratch_reads<=(others=>'0'); fill_index<=0;
      else
        if load_valid='1' and active='0' then mem(to_integer(load_addr))<=load_data; loads<=loads+1; end if;
        if start='1' and active='0' then
          active<='1'; loading<='1'; tile<=(others=>'0'); mode<=filter_mode; shift_latched<=shift_direction;
          wrap_latched<=wrap_edges; scratch_reads<=(others=>'0'); fill_index<=0;
        elsif active='1' and loading='1' then
          if tile(0)='1' then row:=fill_index/4; col:=fill_index mod 4+2;
          else row:=fill_index/6; col:=fill_index mod 6; end if;
          lines(row,col)<=to_unsigned(sample_pixel(mem,(to_integer(tile)/2)*4+row-1,
                                                   (to_integer(tile) mod 2)*4+col-1,wrap_latched),8);
          scratch_reads<=scratch_reads+1;
          if (tile(0)='1' and fill_index=23) or (tile(0)='0' and fill_index=35) then
            loading<='0'; fill_index<=0;
          else fill_index<=fill_index+1; end if;
        elsif active='1' and loading='0' and out_ready='1' then
          if tile=3 then active<='0';
          else
            if tile(0)='0' then
              for r in 0 to 5 loop lines(r,0)<=lines(r,4); lines(r,1)<=lines(r,5); end loop;
            end if;
            tile<=tile+1; loading<='1'; fill_index<=0;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
