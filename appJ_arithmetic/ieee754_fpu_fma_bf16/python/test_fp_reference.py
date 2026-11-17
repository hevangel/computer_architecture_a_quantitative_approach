import math
import random
import struct
import unittest
from fractions import Fraction
from fp_reference import (NV, DZ, OF, UF, NX, QNAN, Result, add, multiply, fma,
                          decode, round32, pow2, bf16_to_fp32, fp8_e5m2_to_fp32,
                          fp8_e4m3fn_to_fp32, fma_low_precision)

def bits(f):
    try:
        return struct.unpack('>I', struct.pack('>f', f))[0]
    except OverflowError:
        return 0xff800000 if f < 0 else 0x7f800000

def host(bits32):
    return struct.unpack('>f', struct.pack('>I', bits32))[0]

class Binary32Tests(unittest.TestCase):
    def test_zero_signs_and_cancellation(self):
        self.assertEqual(add(0x80000000, 0x80000000), Result(0x80000000))
        self.assertEqual(add(0x00000000, 0x80000000, 'RDN'), Result(0x80000000))
        self.assertEqual(add(0x3f800000, 0xbf800000, 'RDN'), Result(0x80000000))
        self.assertEqual(add(0x3f800000, 0xbf800000), Result(0))
        self.assertEqual(multiply(0x80000000, 0x40000000), Result(0x80000000))
        self.assertEqual(fma(0x80000000, 0x40000000, 0x80000000), Result(0x80000000))

    def test_ties_and_directed_rounding(self):
        half_ulp = pow2(-24)
        plus = Fraction(1) + half_ulp
        minus = -plus
        expected = {'RNE':0x3f800000, 'RTZ':0x3f800000, 'RUP':0x3f800001, 'RDN':0x3f800000}
        negative = {'RNE':0xbf800000, 'RTZ':0xbf800000, 'RUP':0xbf800000, 'RDN':0xbf800001}
        for mode in expected:
            self.assertEqual(round32(plus,mode), Result(expected[mode],NX))
            self.assertEqual(round32(minus,mode), Result(negative[mode],NX))
        self.assertEqual(round32(Fraction(1)+3*half_ulp),Result(0x3f800002,NX))

    def test_subnormal_and_after_rounding_tininess(self):
        self.assertEqual(round32(pow2(-149)), Result(1))
        self.assertEqual(round32(pow2(-150)), Result(0,UF|NX))
        self.assertEqual(round32(pow2(-150),'RUP'), Result(1,UF|NX))
        self.assertEqual(round32(-pow2(-150),'RDN'), Result(0x80000001,UF|NX))
        self.assertEqual(round32(pow2(-126)-pow2(-150)), Result(0x00800000,NX))
        self.assertEqual(round32(pow2(-126)-pow2(-150),'RTZ'), Result(0x007fffff,UF|NX))

    def test_overflow_rounding(self):
        for mode, result in [('RNE',0x7f800000), ('RTZ',0x7f7fffff), ('RUP',0x7f800000), ('RDN',0x7f7fffff)]:
            self.assertEqual(multiply(0x7f7fffff,0x40000000,mode),Result(result,OF|NX))
        self.assertEqual(multiply(0xff7fffff,0x40000000,'RUP'), Result(0xff7fffff,OF|NX))
        self.assertEqual(multiply(0xff7fffff,0x40000000,'RDN'), Result(0xff800000,OF|NX))

    def test_nan_inf_and_invalid(self):
        self.assertEqual(add(0x7f800000,0xff800000),Result(QNAN,NV))
        self.assertEqual(multiply(0x7f800000,0),Result(QNAN,NV))
        self.assertEqual(fma(0x7f800000,0x3f800000,0xff800000),Result(QNAN,NV))
        self.assertEqual(add(0x7f800001,0x3f800000),Result(QNAN,NV))
        self.assertEqual(add(0x7fc12345,0x3f800000),Result(QNAN))
        self.assertEqual(fma(0x7f800000,0,0x7fc00000),Result(QNAN,NV))
        self.assertEqual(fma(0x7f800000,0x40000000,0x3f800000),Result(0x7f800000))
        self.assertEqual(DZ,8) # These three operations cannot signal divide-by-zero.

    def test_fused_cancellation_differs_from_unfused(self):
        a,b,c=0x3f800001,0x3f7ffffe,0xbf800000
        self.assertEqual(fma(a,b,c),Result(0xa8800000))
        p=multiply(a,b)
        self.assertEqual(p,Result(0x3f800000,NX))
        self.assertEqual(add(p.bits,c),Result(0))

    def test_fma_rounding_modes_and_low_precision_signaling_nan(self):
        # 1 * 1 + 2^-24 is exactly halfway between adjacent binary32 values.
        for mode, expected in [('RNE',0x3f800000),('RTZ',0x3f800000),
                               ('RUP',0x3f800001),('RDN',0x3f800000)]:
            self.assertEqual(fma(0x3f800000,0x3f800000,0x33800000,mode),Result(expected,NX))
        self.assertEqual(fma_low_precision(0x7d,0x3c,0,'e5m2'),Result(QNAN,NV))
        self.assertEqual(fma_low_precision(0x7f,0x38,0,'e4m3fn'),Result(QNAN))
        self.assertEqual(fma_low_precision(0x8000,0x3f80,0x80000000,'bf16'),Result(0x80000000))

    def test_random_rne_against_host_binary64(self):
        # binary32 add and multiply have enough precision in binary64 for these
        # normal-range inputs; avoid double-rounding at subnormal boundaries.
        rng=random.Random(734)
        for _ in range(4000):
            exp_a=rng.randrange(80,175); exp_b=exp_a+rng.randrange(-20,21)
            a=(rng.randrange(2)<<31)|(exp_a<<23)|rng.randrange(1<<23)
            b=(rng.randrange(2)<<31)|(exp_b<<23)|rng.randrange(1<<23)
            self.assertEqual(add(a,b).bits,bits(host(a)+host(b)),hex(a)+' '+hex(b))
            self.assertEqual(multiply(a,b).bits,bits(host(a)*host(b)),hex(a)+' '+hex(b))

    def test_bfloat_and_all_e5m2_encodings(self):
        self.assertEqual(bf16_to_fp32(0x3f80),0x3f800000)
        self.assertEqual(bf16_to_fp32(0x8000),0x80000000)
        for byte in range(256):
            s,e,f=byte>>7,(byte>>2)&31,byte&3
            actual=fp8_e5m2_to_fp32(byte)
            if e==31:
                self.assertEqual((actual>>23)&255,255)
                self.assertEqual(bool(actual&0x7fffff), bool(f))
                self.assertEqual(actual>>31,s)
            else:
                v=math.ldexp(f,-16) if e==0 else math.ldexp(4+f,e-17)
                if s: v=-v
                self.assertEqual(actual,bits(v),hex(byte))
        self.assertEqual(fp8_e5m2_to_fp32(0x80),0x80000000)

    def test_all_e4m3fn_encodings_and_scaled_fma(self):
        for byte in range(256):
            sign,exp,frac=byte>>7,(byte>>3)&15,byte&7
            actual=fp8_e4m3fn_to_fp32(byte)
            if exp==15 and frac==7:
                self.assertEqual(actual,(sign<<31)|QNAN)
            else:
                value=math.ldexp(frac,-9) if exp==0 else math.ldexp(8+frac,exp-10)
                if sign: value=-value
                self.assertEqual(actual,bits(value),hex(byte))
        self.assertEqual(fp8_e4m3fn_to_fp32(0x7e),bits(448.0))
        self.assertEqual(fma_low_precision(0x38,0x40,0x3f800000,'e4m3fn',2,-1),Result(0x40a00000))
        self.assertEqual(fma_low_precision(0x3f80,0x4000,0xbf800000,'bf16'),Result(0x3f800000))
        self.assertEqual(fma_low_precision(0x3c,0x40,0xbf800000,'e5m2'),Result(0x3f800000))
        self.assertEqual(fma_low_precision(0x3f80,0x3f80,0,'bf16',200,0),Result(0x7f800000,OF|NX))

    def test_bad_inputs(self):
        for action in (lambda: decode(-1),lambda: round32(1,'bad'),lambda: bf16_to_fp32(65536),lambda: fp8_e5m2_to_fp32(256)):
            with self.assertRaises(ValueError): action()

if __name__=='__main__': unittest.main()
