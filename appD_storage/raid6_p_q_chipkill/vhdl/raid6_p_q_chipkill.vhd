library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity raid6_p_q_chipkill is
  port (data_in : in std_logic_vector(31 downto 0); encoded : out std_logic_vector(47 downto 0);
        stripe_in : in std_logic_vector(47 downto 0); erased : in std_logic_vector(5 downto 0);
        recovered : out std_logic_vector(47 downto 0); recover_valid : out std_logic;
        symbols_in : in std_logic_vector(31 downto 0); symbol_encoded : out std_logic_vector(39 downto 0);
        symbol_received : in std_logic_vector(39 downto 0); symbol_corrected : out std_logic_vector(39 downto 0);
        symbol_valid : out std_logic; symbol_error_position : out std_logic_vector(3 downto 0));
end entity;

architecture rtl of raid6_p_q_chipkill is
  function mul8(a,b : std_logic_vector(7 downto 0)) return std_logic_vector is
    variable x,y,z : unsigned(7 downto 0);
  begin
    x:=unsigned(a); y:=unsigned(b); z:=(others=>'0');
    for i in 0 to 7 loop
      if y(0)='1' then z:=z xor x; end if;
      if x(7)='1' then x:=shift_left(x,1) xor x"1d"; else x:=shift_left(x,1); end if;
      y:=shift_right(y,1);
    end loop;
    return std_logic_vector(z);
  end;
  function div8(a,b : std_logic_vector(7 downto 0)) return std_logic_vector is
    variable x,y : std_logic_vector(7 downto 0);
  begin
    x:=x"01"; y:=b;
    for i in 0 to 7 loop
      if i>0 then x:=mul8(x,y); end if;
      y:=mul8(y,y);
    end loop;
    return mul8(a,x);
  end;
  function mul4(a,b : std_logic_vector(3 downto 0)) return std_logic_vector is
    variable x,y,z : unsigned(3 downto 0);
  begin
    x:=unsigned(a); y:=unsigned(b); z:=(others=>'0');
    for i in 0 to 3 loop
      if y(0)='1' then z:=z xor x; end if;
      if x(3)='1' then x:=shift_left(x,1) xor x"3"; else x:=shift_left(x,1); end if;
      y:=shift_right(y,1);
    end loop;
    return std_logic_vector(z);
  end;
  function coeff8(i : integer) return std_logic_vector is
  begin
    case i is when 0=>return x"01"; when 1=>return x"02"; when 2=>return x"04"; when others=>return x"08"; end case;
  end;
begin
  process(all)
    variable p,q,pr,qr,x : std_logic_vector(7 downto 0);
    variable d : std_logic_vector(31 downto 0);
    variable sp,sq,cp,cq,c4 : std_logic_vector(3 downto 0);
    variable corr : std_logic_vector(39 downto 0);
    variable count,first,second,nd : integer;
    variable found : boolean;
  begin
    p:=(others=>'0'); q:=(others=>'0');
    for i in 0 to 3 loop
      p:=p xor data_in(i*8+7 downto i*8); q:=q xor mul8(data_in(i*8+7 downto i*8),coeff8(i));
    end loop;
    encoded<=q & p & data_in;
    count:=0; first:=0; second:=0; nd:=0;
    for i in 0 to 5 loop if erased(i)='1' then count:=count+1; end if; end loop;
    d:=stripe_in(31 downto 0); pr:=(others=>'0'); qr:=(others=>'0');
    if erased(4)='0' then pr:=stripe_in(39 downto 32); end if;
    if erased(5)='0' then qr:=stripe_in(47 downto 40); end if;
    for i in 0 to 3 loop
      if erased(i)='1' then
        if nd=0 then first:=i; else second:=i; end if; nd:=nd+1;
      else
        pr:=pr xor stripe_in(i*8+7 downto i*8);
        qr:=qr xor mul8(stripe_in(i*8+7 downto i*8),coeff8(i));
      end if;
    end loop;
    if count<=2 and nd=1 then
      if erased(4)='0' then x:=pr; else x:=div8(qr,coeff8(first)); end if;
      d(first*8+7 downto first*8):=x;
    elsif count<=2 and nd=2 then
      x:=div8(qr xor mul8(coeff8(second),pr),coeff8(first) xor coeff8(second));
      d(first*8+7 downto first*8):=x; d(second*8+7 downto second*8):=pr xor x;
    end if;
    p:=(others=>'0'); q:=(others=>'0');
    for i in 0 to 3 loop p:=p xor d(i*8+7 downto i*8); q:=q xor mul8(d(i*8+7 downto i*8),coeff8(i)); end loop;
    recovered<=q & p & d;
    if count<=2 then recover_valid<='1'; else recover_valid<='0'; end if;
    cp:=(others=>'0'); cq:=(others=>'0'); c4:=x"1";
    for i in 0 to 7 loop
      cp:=cp xor symbols_in(i*4+3 downto i*4); cq:=cq xor mul4(symbols_in(i*4+3 downto i*4),c4); c4:=mul4(c4,x"2");
    end loop;
    symbol_encoded<=cq & cp & symbols_in;
    cp:=(others=>'0'); cq:=(others=>'0'); c4:=x"1";
    for i in 0 to 7 loop
      cp:=cp xor symbol_received(i*4+3 downto i*4); cq:=cq xor mul4(symbol_received(i*4+3 downto i*4),c4); c4:=mul4(c4,x"2");
    end loop;
    sp:=cp xor symbol_received(35 downto 32); sq:=cq xor symbol_received(39 downto 36);
    corr:=symbol_received; symbol_valid<='1'; symbol_error_position<=x"f"; found:=false; c4:=x"1";
    if sp=x"0" and sq=x"0" then null;
    elsif sq=x"0" then corr(35 downto 32):=corr(35 downto 32) xor sp; symbol_error_position<=x"8";
    elsif sp=x"0" then corr(39 downto 36):=corr(39 downto 36) xor sq; symbol_error_position<=x"9";
    else
      for i in 0 to 7 loop
        if not found and mul4(sp,c4)=sq then
          corr(i*4+3 downto i*4):=corr(i*4+3 downto i*4) xor sp;
          symbol_error_position<=std_logic_vector(to_unsigned(i,4)); found:=true;
        end if;
        c4:=mul4(c4,x"2");
      end loop;
      if not found then symbol_valid<='0'; end if;
    end if;
    symbol_corrected<=corr;
  end process;
end architecture;
