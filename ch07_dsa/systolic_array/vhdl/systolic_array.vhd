-- Weight-stationary N x N systolic matrix-multiply unit, the core of Google's TPU (Chapter 7).
--
--   C[m][n] = sum_k A[m][k] * W[k][n]        A: int8 activations   W: int8 weights   C: int32
--
-- Each PE(k,n) holds weight W[k][n].  Activations flow left-to-right, partial sums top-to-bottom.
-- One activation row A[m][*] is presented per cycle; row k is delayed by k cycles on the way in
-- (the "skew") so that each wavefront meets the right partial sum, and column n is delayed by
-- N-1-n cycles on the way out so a whole result row C[m][*] appears together.
-- (VHDL is case-insensitive, so the size generic is DIM rather than N: loop variable n would clash.)
-- Latency: a row presented in cycle m is valid at c_out in cycle m + 2N - 1; throughput is one
-- row per cycle -- N*N MACs per cycle once the pipeline is full.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity systolic_array is
  generic (DIM : positive := 4; DATA_W : positive := 8; ACC_W : positive := 32);
  port (
    clk, rst_n : in  std_logic;
    -- weight load: write row w_row of W (N weights per write)
    w_we       : in  std_logic;
    w_row      : in  natural range 0 to DIM-1;
    w_data     : in  std_logic_vector(DIM*DATA_W-1 downto 0);
    -- activation stream: one row of A per cycle
    in_valid   : in  std_logic;
    a_in       : in  std_logic_vector(DIM*DATA_W-1 downto 0);
    -- result stream: one row of C per cycle, 2N-1 cycles later
    out_valid  : out std_logic;
    c_out      : out std_logic_vector(DIM*ACC_W-1 downto 0)
  );
end entity;

architecture rtl of systolic_array is
  constant LAT : positive := 2 * DIM - 1;
  type data_arr is array (0 to DIM*DIM-1) of signed(DATA_W-1 downto 0);
  type acc_arr  is array (0 to DIM*DIM-1) of signed(ACC_W-1 downto 0);
  signal wt    : data_arr := (others => (others => '0'));   -- stationary weights, index k*DIM+n
  signal a_reg : data_arr := (others => (others => '0'));   -- activation register in PE(k,n)
  signal p_reg : acc_arr  := (others => (others => '0'));   -- partial-sum register in PE(k,n)
  signal dl    : data_arr := (others => (others => '0'));   -- input skew lines: row k uses dl(k*DIM + 0 .. k-1)
  signal od    : acc_arr  := (others => (others => '0'));   -- output de-skew: column n uses od(n*DIM + 0 .. DIM-2-n)
  signal vpipe : std_logic_vector(LAT-1 downto 0) := (others => '0');

  signal a_w  : data_arr;                                   -- activation entering PE(k,n)
  signal p_w  : acc_arr;                                    -- partial sum entering PE(k,n)
  signal prod : acc_arr;
begin
  comb : process (all)
  begin
    for k in 0 to DIM-1 loop
      for n in 0 to DIM-1 loop
        if n = 0 then
          if k = 0 then a_w(k*DIM+n) <= signed(a_in(DATA_W-1 downto 0));
          else          a_w(k*DIM+n) <= dl(k*DIM + k - 1);
          end if;
        else
          a_w(k*DIM+n) <= a_reg(k*DIM + n - 1);
        end if;
        if k = 0 then p_w(k*DIM+n) <= (others => '0');
        else          p_w(k*DIM+n) <= p_reg((k-1)*DIM + n);
        end if;
      end loop;
    end loop;
  end process;

  -- multiplier array
  mac : for i in 0 to DIM*DIM-1 generate
    prod(i) <= resize(a_w(i) * wt(i), ACC_W);
  end generate;

  outputs : process (all)
  begin
    for n in 0 to DIM-1 loop
      if n = DIM-1 then c_out(n*ACC_W + ACC_W-1 downto n*ACC_W) <= std_logic_vector(p_reg((DIM-1)*DIM + n));
      else             c_out(n*ACC_W + ACC_W-1 downto n*ACC_W) <= std_logic_vector(od(n*DIM + (DIM - 2 - n)));
      end if;
    end loop;
  end process;
  out_valid <= vpipe(LAT-1);

  seq : process (clk, rst_n)
  begin
    if rst_n = '0' then
      vpipe <= (others => '0');
      a_reg <= (others => (others => '0'));  p_reg <= (others => (others => '0'));
      dl    <= (others => (others => '0'));  od    <= (others => (others => '0'));
    elsif rising_edge(clk) then
      vpipe <= vpipe(LAT-2 downto 0) & in_valid;
      for i in 0 to DIM*DIM-1 loop
        a_reg(i) <= a_w(i);
        p_reg(i) <= p_w(i) + prod(i);                          -- the MAC
      end loop;
      for k in 1 to DIM-1 loop                                   -- input skew: row k delayed k cycles
        dl(k*DIM) <= signed(a_in(k*DATA_W + DATA_W-1 downto k*DATA_W));
        for j in 1 to k-1 loop dl(k*DIM + j) <= dl(k*DIM + j - 1); end loop;
      end loop;
      for n in 0 to DIM-2 loop                                   -- output de-skew: column n delayed DIM-1-n
        od(n*DIM) <= p_reg((DIM-1)*DIM + n);
        for j in 1 to DIM-2-n loop od(n*DIM + j) <= od(n*DIM + j - 1); end loop;
      end loop;
    end if;
  end process;

  wload : process (clk)
  begin
    if rising_edge(clk) and w_we = '1' then
      for n in 0 to DIM-1 loop
        wt(w_row*DIM + n) <= signed(w_data(n*DATA_W + DATA_W-1 downto n*DATA_W));
      end loop;
    end if;
  end process;
end architecture;
