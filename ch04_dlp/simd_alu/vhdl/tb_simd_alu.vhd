-- 1. Directed cases: carry isolation between lanes (the point of a partitioned adder) and saturation.
-- 2. Every op x every lane width it supports, 300 pseudo-random + edge-pattern operand pairs each, against a golden model that rebuilds each lane bit by bit
--    and uses plain 64-bit integer arithmetic (a different structure from the RTL's masks and shifts).
-- 3. Multimedia kernels against scalar loops, with instruction counts:
--      brightness (saturating add of 64 pixels), SAD of an 8x8 block, 16-bit dot product (PMADD), saturating audio mix.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_simd_alu is end entity;

architecture sim of tb_simd_alu is
  type i64 is range -(2**56) to 2**56;
  subtype w64 is std_logic_vector(63 downto 0);
  signal esize : natural range 0 to 2 := 0;
  signal op : natural range 0 to 31 := 0;
  signal a, b, y : w64 := (others => '0');
  signal imm : natural range 0 to 63 := 0;

  -- ---- golden model ---------------------------------------------------------------------------------
  function pow2(k : natural) return i64 is
    variable r : i64 := 1;
  begin
    for i in 1 to k loop r := r * 2; end loop;
    return r;
  end function;
  function lane_u(v : w64; lw, l : natural) return i64 is          -- unsigned lane value, rebuilt bit by bit
    variable r : i64 := 0;
  begin
    for k in 0 to lw - 1 loop if v(l * lw + k) = '1' then r := r + pow2(k); end if; end loop;
    return r;
  end function;
  function to_s(u : i64; lw : natural) return i64 is               -- two's-complement interpretation
  begin
    if u >= pow2(lw - 1) then return u - pow2(lw); else return u; end if;
  end function;
  procedure put_lane(variable out64 : inout w64; l, lw : natural; r : i64) is   -- store the low lw bits of r (two's complement)
    variable r2 : i64;
  begin
    r2 := r mod pow2(lw);
    for k in 0 to lw - 1 loop
      if (r2 / pow2(k)) mod 2 = 1 then out64(l * lw + k) := '1'; else out64(l * lw + k) := '0'; end if;
    end loop;
  end procedure;

  function ref_op(opc, es : natural; x, z : w64; sh : natural) return w64 is
    variable lw, nl : natural;
    variable ux, uz, sx, sz, res, hi, lo, fullv, acc, p : i64;
    variable out64 : w64 := (others => '0');
  begin
    lw := 8 * 2 ** es;  nl := 64 / lw;
    fullv := pow2(lw) - 1;  hi := pow2(lw - 1) - 1;  lo := -pow2(lw - 1);
    if opc = 14 then                                                -- PMADD
      for i in 0 to 1 loop
        acc := to_s(lane_u(x, 16, 2*i), 16) * to_s(lane_u(z, 16, 2*i), 16) + to_s(lane_u(x, 16, 2*i + 1), 16) * to_s(lane_u(z, 16, 2*i + 1), 16);
        put_lane(out64, i, 32, acc);
      end loop;
      return out64;
    end if;
    if opc = 18 then                                                -- PSAD
      acc := 0;
      for l in 0 to 7 loop
        ux := lane_u(x, 8, l);  uz := lane_u(z, 8, l);
        if ux > uz then acc := acc + (ux - uz); else acc := acc + (uz - ux); end if;
      end loop;
      put_lane(out64, 0, 16, acc);
      return out64;
    end if;
    for l in 0 to nl - 1 loop
      ux := lane_u(x, lw, l);  uz := lane_u(z, lw, l);  sx := to_s(ux, lw);  sz := to_s(uz, lw);  res := 0;
      case opc is
        when 0  => res := ux + uz;
        when 1  => res := ux - uz;
        when 2  => res := sx + sz;  if res > hi then res := hi; elsif res < lo then res := lo; end if;
        when 3  => res := sx - sz;  if res > hi then res := hi; elsif res < lo then res := lo; end if;
        when 4  => res := ux + uz;  if res > fullv then res := fullv; end if;
        when 5  => res := ux - uz;  if res < 0 then res := 0; end if;
        when 6  => if ux < uz then res := ux; else res := uz; end if;
        when 7  => if ux > uz then res := ux; else res := uz; end if;
        when 8  => if sx < sz then res := sx; else res := sz; end if;
        when 9  => if sx > sz then res := sx; else res := sz; end if;
        when 10 => res := (ux + uz + 1) / 2;
        when 11 => if ux = uz then res := -1; end if;
        when 12 => if sx > sz then res := -1; end if;
        when 13 => p := ux * (uz mod 65536) + ((ux * (uz / 65536)) mod 65536) * 65536;     -- low 32 bits of the product without overflowing 64 bits
                   res := p;
        when 15 => if sh < lw then res := (ux mod pow2(lw - sh)) * pow2(sh); end if;        -- bits shifted out the top are dropped
        when 16 => if sh < lw then res := ux / pow2(sh); end if;
        when 17 => if sh >= lw then
                     if sx < 0 then res := -1; end if;
                   else
                     res := (sx - (sx mod pow2(sh))) / pow2(sh);                            -- floor division == arithmetic shift
                   end if;
        when others => res := 0;
      end case;
      put_lane(out64, l, lw, res);
    end loop;
    return out64;
  end function;

  function splat8(v : natural) return w64 is
  begin return std_logic_vector(to_unsigned(v, 8)) & std_logic_vector(to_unsigned(v, 8)) & std_logic_vector(to_unsigned(v, 8)) & std_logic_vector(to_unsigned(v, 8)) &
               std_logic_vector(to_unsigned(v, 8)) & std_logic_vector(to_unsigned(v, 8)) & std_logic_vector(to_unsigned(v, 8)) & std_logic_vector(to_unsigned(v, 8)); end function;
begin
  dut : entity work.simd_alu port map (esize, op, a, b, imm, y);

  stim : process
    variable errors, simd_ops, n_checked : natural := 0;
    variable seed : unsigned(31 downto 0) := to_unsigned(1997, 32);
    variable g, x, z, rg : w64;
    variable sh : natural;
    variable es_lo, es_hi : natural;
    type name_arr is array (0 to 18) of string(1 to 7);
    constant opname : name_arr := ("PADD   ", "PSUB   ", "PADDS  ", "PSUBS  ", "PADDUS ", "PSUBUS ", "PMINU  ", "PMAXU  ", "PMINS  ", "PMAXS  ",
                                   "PAVGU  ", "PCMPEQ ", "PCMPGTS", "PMULLO ", "PMADD  ", "PSLL   ", "PSRL   ", "PSRA   ", "PSAD   ");

    impure function rnd64 return w64 is
      variable v : w64;
    begin
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);  v(63 downto 32) := std_logic_vector(seed);
      seed := resize(seed * to_unsigned(1664525, 32) + to_unsigned(1013904223, 32), 32);  v(31 downto 0)  := std_logic_vector(seed);
      return v;
    end function;

    procedure run(opc, es : natural; xv, zv : w64; shv : natural; variable r : out w64) is
    begin
      op <= opc;  esize <= es;  a <= xv;  b <= zv;  imm <= shv;
      wait for 1 ns;
      simd_ops := simd_ops + 1;
      r := y;
    end procedure;
    procedure chk(what : string; opc, es : natural; xv, zv, exp_v, mask : w64) is
      variable r : w64;
    begin
      run(opc, es, xv, zv, 0, r);
      if (r and mask) /= exp_v then errors := errors + 1; report "FAIL " & what severity error; end if;
    end procedure;

    type u8_arr is array (0 to 63) of natural;
    type s16_arr is array (0 to 31) of integer;
    variable img : u8_arr;
    variable px, sat, wrap, cur, ref_row, pa, pb, pm, acc, s : w64;
    variable mism, wrapped, total, ssum, sv : integer;
    variable va, vb, sx16, sy16 : s16_arr;
    variable dot : i64;
    variable lsum : unsigned(31 downto 0);
    variable ones : w64 := (others => '1');
    variable t : natural;
  begin
    -- ---- 1. directed -------------------------------------------------------------------------------
    chk("PADD 8-bit  FF+01 per even byte -> 00 (no carry into the next byte)", 0, 0, x"00FF00FF00FF00FF", x"0001000100010001", x"0000000000000000", ones);
    chk("PADD 16-bit 00FF+0001 -> 0100 inside the lane",                       0, 1, x"00FF00FF00FF00FF", x"0001000100010001", x"0100010001000100", ones);
    chk("PADD 32-bit FFFFFFFF+1 -> 0, upper lane untouched",                   0, 2, x"00000001FFFFFFFF", x"0000000000000001", x"0000000100000000", ones);
    chk("PSUB 8-bit  [00-01, 01-00] -> [FF, 01]: the borrow stays in its byte", 1, 0, x"0100010001000100", x"0001000100010001", x"01FF01FF01FF01FF", ones);
    chk("PADDUS 8-bit F0+20 -> FF",                          4, 0, splat8(16#F0#), splat8(16#20#), splat8(16#FF#), ones);
    chk("PADD   8-bit F0+20 -> 10 (wraps: the artifact saturation avoids)", 0, 0, splat8(16#F0#), splat8(16#20#), splat8(16#10#), ones);
    chk("PADDS  8-bit 70+20 -> 7F",                          2, 0, splat8(16#70#), splat8(16#20#), splat8(16#7F#), ones);
    chk("PADDS  8-bit 80+80 -> 80",                          2, 0, splat8(16#80#), splat8(16#80#), splat8(16#80#), ones);
    chk("PSUBUS 8-bit 10-20 -> 00",                          5, 0, splat8(16#10#), splat8(16#20#), x"0000000000000000", ones);
    chk("PSUBS  8-bit 80-01 -> 80",                          3, 0, splat8(16#80#), splat8(16#01#), splat8(16#80#), ones);
    chk("PAVGU  8-bit (255+254+1)/2 -> FF",                  10, 0, splat8(16#FF#), splat8(16#FE#), splat8(16#FF#), ones);
    chk("PSAD   |1-0| + |0-3| + 6 x |5-5| = 4",              18, 0, x"0505050505050001", x"0505050505050300", x"0000000000000004", x"000000000000FFFF");
    chk("PMADD  (1*3 + 2*4) = 11,  (-5*2 + 7*3) = 11",        14, 1, x"0007FFFB00020001", x"0003000200040003", x"0000000B0000000B", ones);

    -- ---- 2. every op x lane width --------------------------------------------------------------------
    for opc in 0 to 18 loop
      es_lo := 0;  es_hi := 2;
      if opc = 14 then es_lo := 1; es_hi := 1; end if;
      if opc = 18 then es_lo := 0; es_hi := 0; end if;
      for es in es_lo to es_hi loop
        for tt in 0 to 299 loop
          x := rnd64;  z := rnd64;  g := rnd64;
          sh := to_integer(unsigned(g(5 downto 0))) mod (8 * 2 ** es + 2);                -- shift counts include >= width
          case tt mod 10 is                                                              -- edge-heavy operands
            when 0 => x := (others => '0');
            when 1 => z := (others => '1');
            when 2 => x := x"8080808080808080";  z := x"8080808080808080";
            when 3 => x := x"7F7F7F7F7F7F7F7F";  z := x"0101010101010101";
            when others => null;
          end case;
          run(opc, es, x, z, sh, g);
          rg := ref_op(opc, es, x, z, sh);
          if g /= rg then
            errors := errors + 1;
            if errors < 20 then report "FAIL " & opname(opc) & " esize=" & integer'image(es) & " imm=" & integer'image(sh) severity error; end if;
          end if;
          n_checked := n_checked + 1;
        end loop;
      end loop;
    end loop;
    report integer'image(n_checked) & " op/width/operand combinations checked against the golden model";

    -- ---- 3. kernels -----------------------------------------------------------------------------------
    -- brightness: saturating add of +90 to 64 pixels
    for i in 0 to 63 loop g := rnd64;  img(i) := to_integer(unsigned(g(7 downto 0))); end loop;
    mism := 0;  wrapped := 0;  simd_ops := 0;
    for c in 0 to 7 loop
      for k in 0 to 7 loop px(8*k + 7 downto 8*k) := std_logic_vector(to_unsigned(img(8*c + k), 8)); end loop;
      run(4, 0, px, splat8(90), 0, sat);                                                -- PADDUS
      run(0, 0, px, splat8(90), 0, wrap);                                               -- PADD  (what a plain wide add would do)
      for k in 0 to 7 loop
        sv := img(8*c + k) + 90;  if sv > 255 then sv := 255; end if;
        if to_integer(unsigned(sat(8*k + 7 downto 8*k))) /= sv then mism := mism + 1; end if;
        if wrap(8*k + 7 downto 8*k) /= sat(8*k + 7 downto 8*k) then wrapped := wrapped + 1; end if;
      end loop;
    end loop;
    if mism /= 0 then errors := errors + 1; report "FAIL brightness mismatches" severity error; end if;
    total := 0;  for i in 0 to 63 loop if img(i) + 90 > 255 then total := total + 1; end if; end loop;
    if wrapped /= total or total = 0 then errors := errors + 1; report "FAIL brightness: saturating vs wrapping difference" severity error; end if;
    report "brightness : 64 pixels, " & integer'image(simd_ops / 2) & " saturating SIMD adds (+" & integer'image(simd_ops / 2) & " wrapping adds for comparison) vs 64 scalar ops; " &
           integer'image(total) & " pixels would wrap without saturation";

    -- SAD of an 8x8 block (motion estimation)
    ssum := 0;  acc := (others => '0');  simd_ops := 0;
    for r in 0 to 7 loop
      cur := rnd64;  ref_row := rnd64;
      run(18, 0, cur, ref_row, 0, s);
      acc := std_logic_vector(unsigned(acc) + unsigned(s(15 downto 0)));
      for k in 0 to 7 loop
        if unsigned(cur(8*k + 7 downto 8*k)) > unsigned(ref_row(8*k + 7 downto 8*k)) then
          ssum := ssum + to_integer(unsigned(cur(8*k + 7 downto 8*k))) - to_integer(unsigned(ref_row(8*k + 7 downto 8*k)));
        else
          ssum := ssum + to_integer(unsigned(ref_row(8*k + 7 downto 8*k))) - to_integer(unsigned(cur(8*k + 7 downto 8*k)));
        end if;
      end loop;
    end loop;
    if to_integer(unsigned(acc)) /= ssum then errors := errors + 1; report "FAIL SAD" severity error; end if;
    report "SAD 8x8    : " & integer'image(simd_ops) & " PSAD instructions (+ adds) vs 64 scalar absolute-difference steps, SAD = " & integer'image(ssum);

    -- 16-bit dot product with PMADD, 32 elements
    for i in 0 to 31 loop
      g := rnd64;  va(i) := to_integer(signed(g(15 downto 0)));
      g := rnd64;  vb(i) := to_integer(signed(g(15 downto 0)));
    end loop;
    dot := 0;  for i in 0 to 31 loop dot := dot + i64(va(i)) * i64(vb(i)); end loop;
    simd_ops := 0;  acc := (others => '0');
    for c in 0 to 7 loop
      for k in 0 to 3 loop
        pa(16*k + 15 downto 16*k) := std_logic_vector(to_signed(va(4*c + k), 16));
        pb(16*k + 15 downto 16*k) := std_logic_vector(to_signed(vb(4*c + k), 16));
      end loop;
      run(14, 1, pa, pb, 0, pm);                                                        -- PMADD -> two 32-bit partial sums
      run(0, 2, acc, pm, 0, acc);                                                       -- PADD (32-bit lanes) accumulates
    end loop;
    lsum := unsigned(acc(31 downto 0)) + unsigned(acc(63 downto 32));                    -- horizontal add of the two lanes
    if to_integer(lsum(15 downto 0)) /= integer(dot mod 65536) or to_integer(lsum(31 downto 16)) /= integer((dot / 65536) mod 65536) then
      errors := errors + 1;  report "FAIL dot product" severity error;
    end if;
    report "dot product: 32 MACs in " & integer'image(simd_ops) & " SIMD instructions (8 PMADD + 8 PADD) vs 64 scalar multiply/add ops";

    -- saturating 16-bit audio mix of two 32-sample buffers
    for i in 0 to 31 loop
      g := rnd64;  sx16(i) := to_integer(signed(g(15 downto 0)));
      g := rnd64;  sy16(i) := to_integer(signed(g(15 downto 0)));
    end loop;
    mism := 0;  simd_ops := 0;
    for c in 0 to 7 loop
      for k in 0 to 3 loop
        pa(16*k + 15 downto 16*k) := std_logic_vector(to_signed(sx16(4*c + k), 16));
        pb(16*k + 15 downto 16*k) := std_logic_vector(to_signed(sy16(4*c + k), 16));
      end loop;
      run(2, 1, pa, pb, 0, pm);                                                         -- PADDS
      for k in 0 to 3 loop
        sv := sx16(4*c + k) + sy16(4*c + k);  if sv > 32767 then sv := 32767; end if;  if sv < -32768 then sv := -32768; end if;
        if to_integer(signed(pm(16*k + 15 downto 16*k))) /= sv then mism := mism + 1; end if;
      end loop;
    end loop;
    if mism /= 0 then errors := errors + 1; report "FAIL audio mix" severity error; end if;
    report "audio mix  : 32 samples in " & integer'image(simd_ops) & " saturating SIMD adds vs 32 scalar adds + clamps";

    if errors = 0 then report "TEST PASSED";
    else report "TEST FAILED: " & integer'image(errors) & " errors" severity error;
    end if;
    finish;
  end process;
end architecture;
