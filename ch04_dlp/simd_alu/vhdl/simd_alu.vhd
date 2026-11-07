-- A 64-bit packed-subword SIMD ALU (Chapter 4: SIMD instruction-set extensions such as MMX / SSE / AVX).
--
-- One 64-bit register is treated as 8 x 8-bit, 4 x 16-bit or 2 x 32-bit lanes (esize = 0, 1, 2) and one instruction operates on every lane at once:
-- "subword parallelism" -- the existing wide datapath does 8 byte operations instead of 1.
--
--   op  name     per lane                                                  op  name     per lane
--    0  PADD     a + b (wraps)                                             10  PAVGU    (a + b + 1) >> 1, unsigned (rounding average)
--    1  PSUB     a - b (wraps)                                             11  PCMPEQ   all ones if a == b else 0
--    2  PADDS    signed saturating add                                     12  PCMPGTS  all ones if a > b (signed) else 0
--    3  PSUBS    signed saturating subtract                                13  PMULLO   low half of a * b
--    4  PADDUS   unsigned saturating add                                   14  PMADD    (esize 1 only) y32[i] = a[2i]*b[2i] + a[2i+1]*b[2i+1], signed
--    5  PSUBUS   unsigned saturating subtract (floors at 0)                15  PSLL     a << imm  (0 when imm >= lane width)
--    6  PMINU    unsigned minimum                                          16  PSRL     a >> imm  logical
--    7  PMAXU    unsigned maximum                                          17  PSRA     a >> imm  arithmetic (sign fill when imm >= width)
--    8  PMINS    signed minimum                                            18  PSAD     (esize 0 only) y(15:0) = sum over 8 bytes of |a - b|, rest 0
--    9  PMAXS    signed maximum
--
-- PADD and PSUB are implemented the way hardware does it: ONE 64-bit adder/subtractor whose carry (borrow) is killed at every lane boundary
-- by handling the lane MSBs separately ("SWAR"):   sum = ((a and not H) + (b and not H)) xor ((a xor b) and H),   H = the lane MSB mask.
-- Everything else is computed lane by lane.  Purely combinational.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity simd_alu is
  port (
    esize : in  natural range 0 to 2;                   -- 0: 8-bit lanes, 1: 16-bit, 2: 32-bit
    op    : in  natural range 0 to 31;
    a, b  : in  std_logic_vector(63 downto 0);
    imm   : in  natural range 0 to 63;                  -- shift count
    y     : out std_logic_vector(63 downto 0)
  );
end entity;

architecture rtl of simd_alu is
begin
  process (all)
    variable h, sum_swar, diff_swar, lmask, res_y : unsigned(63 downto 0);
    variable ua, ub, ur : unsigned(63 downto 0);
    variable sa, sb, sr, smax, smin : signed(63 downto 0);
    variable lw, nl : natural;
    variable acc : signed(31 downto 0);
    variable s16 : unsigned(15 downto 0);
    variable ua8, ub8 : unsigned(7 downto 0);
    variable one : unsigned(63 downto 0) := to_unsigned(1, 64);
  begin
    case esize is
      when 0 => h := x"8080808080808080";
      when 1 => h := x"8000800080008000";
      when others => h := x"8000000080000000";
    end case;
    sum_swar  := ((unsigned(a) and not h) + (unsigned(b) and not h)) xor ((unsigned(a) xor unsigned(b)) and h);   -- one adder, carries cannot cross a lane boundary
    diff_swar := ((unsigned(a) or h) - (unsigned(b) and not h)) xor ((unsigned(a) xor not unsigned(b)) and h);    -- one subtractor, borrows cannot cross
    lw := 8 * 2 ** esize;  nl := 64 / lw;
    lmask := shift_left(one, lw) - 1;
    smax := signed(shift_left(one, lw - 1)) - 1;  smin := -signed(shift_left(one, lw - 1));
    res_y := (others => '0');

    if op = 0 then res_y := sum_swar;
    elsif op = 1 then res_y := diff_swar;
    elsif op = 14 then                                                              -- PMADD: signed 16x16 products added in pairs -> 32-bit lanes
      for i in 0 to 1 loop
        acc := resize(signed(a(32*i + 15 downto 32*i)) * signed(b(32*i + 15 downto 32*i)), 32)
             + resize(signed(a(32*i + 31 downto 32*i + 16)) * signed(b(32*i + 31 downto 32*i + 16)), 32);
        res_y(32*i + 31 downto 32*i) := unsigned(acc);
      end loop;
    elsif op = 18 then                                                              -- PSAD: sum of absolute differences of 8 unsigned bytes
      s16 := (others => '0');
      for i in 0 to 7 loop
        ua8 := unsigned(a(8*i + 7 downto 8*i));  ub8 := unsigned(b(8*i + 7 downto 8*i));
        if ua8 > ub8 then s16 := s16 + resize(ua8 - ub8, 16); else s16 := s16 + resize(ub8 - ua8, 16); end if;
      end loop;
      res_y(15 downto 0) := s16;
    else
      for l in 0 to 7 loop
        if l < nl then
          ua := shift_right(unsigned(a), l * lw) and lmask;  ub := shift_right(unsigned(b), l * lw) and lmask;      -- unsigned lane values
          sa := shift_right(signed(shift_left(ua, 64 - lw)), 64 - lw);                                           -- sign-extended lane values
          sb := shift_right(signed(shift_left(ub, 64 - lw)), 64 - lw);
          ur := (others => '0');  sr := (others => '0');
          case op is
            when 2  => sr := sa + sb;  if sr > smax then sr := smax; end if;  if sr < smin then sr := smin; end if;  ur := unsigned(sr);
            when 3  => sr := sa - sb;  if sr > smax then sr := smax; end if;  if sr < smin then sr := smin; end if;  ur := unsigned(sr);
            when 4  => ur := ua + ub;  if ur > lmask then ur := lmask; end if;
            when 5  => if ua > ub then ur := ua - ub; end if;
            when 6  => if ua < ub then ur := ua; else ur := ub; end if;
            when 7  => if ua > ub then ur := ua; else ur := ub; end if;
            when 8  => if sa < sb then ur := unsigned(sa); else ur := unsigned(sb); end if;
            when 9  => if sa > sb then ur := unsigned(sa); else ur := unsigned(sb); end if;
            when 10 => ur := shift_right(ua + ub + 1, 1);
            when 11 => if ua = ub then ur := (others => '1'); end if;
            when 12 => if sa > sb then ur := (others => '1'); end if;
            when 13 => ur := resize(ua * ub, 64);
            when 15 => if imm < lw then ur := shift_left(ua, imm); end if;
            when 16 => if imm < lw then ur := shift_right(ua, imm); end if;
            when 17 => if imm >= lw then sr := shift_right(sa, 63); else sr := shift_right(sa, imm); end if;  ur := unsigned(sr);
            when others => null;
          end case;
          res_y := res_y or shift_left(ur and lmask, l * lw);
        end if;
      end loop;
    end if;
    y <= std_logic_vector(res_y);
  end process;
end architecture;
