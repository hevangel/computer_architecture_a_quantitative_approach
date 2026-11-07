`timescale 1ns/1ps
// 1. Directed cases: carry isolation between lanes (the point of a partitioned adder) and saturation.
// 2. Every op x every lane width it supports, 300 pseudo-random + edge-pattern operand pairs each, against a golden model that rebuilds each lane bit by bit
//    and uses plain 64-bit integer arithmetic (a different structure from the RTL's masks and shifts).
// 3. Multimedia kernels against scalar loops, with instruction counts:
//      brightness (saturating add of 64 pixels), SAD of an 8x8 block, 16-bit dot product (PMADD), saturating audio mix.
module tb_simd_alu;
  logic [1:0] esize = 0;  logic [4:0] op = 0;  logic [63:0] a = 0, b = 0;  logic [5:0] imm = 0;  logic [63:0] y;
  simd_alu dut (.*);

  int errors = 0, simd_ops = 0;
  logic [31:0] seed = 32'd1997;
  function automatic logic [63:0] rnd64();
    logic [63:0] v;
    seed = seed * 32'd1664525 + 32'd1013904223;  v[63:32] = seed;
    seed = seed * 32'd1664525 + 32'd1013904223;  v[31:0]  = seed;
    return v;
  endfunction

  function automatic logic [7:0]  rnd8();  logic [63:0] v; v = rnd64(); return v[7:0];  endfunction     // (Icarus: no part-select of a function call)
  function automatic logic [15:0] rnd16(); logic [63:0] v; v = rnd64(); return v[15:0]; endfunction
  function automatic logic [5:0]  rnd6();  logic [63:0] v; v = rnd64(); return v[5:0];  endfunction

  // ---- golden model --------------------------------------------------------------------------------
  function automatic longint lane_u(input logic [63:0] v, input int lw, input int l);   // unsigned lane value, rebuilt bit by bit
    longint r;  r = 0;
    for (int k = 0; k < lw; k++) if (v[l * lw + k]) r = r + (64'sd1 <<< k);
    return r;
  endfunction
  function automatic longint to_s(input longint u, input int lw);                      // two's-complement interpretation
    if (u >= (64'sd1 <<< (lw - 1))) return u - (64'sd1 <<< lw); else return u;
  endfunction
  function automatic logic [63:0] ref_op(input int opc, input int es, input logic [63:0] x, input logic [63:0] z, input int sh);
    int lw, nl;  longint ux, uz, sx, sz, res, hi, lo, full;  logic [63:0] out;  longint acc;
    lw = 8 << es;  nl = 64 / lw;  out = 64'd0;  full = (64'sd1 <<< lw) - 1;
    hi = (64'sd1 <<< (lw - 1)) - 1;  lo = -(64'sd1 <<< (lw - 1));
    if (opc == 14) begin                                                               // PMADD
      for (int i = 0; i < 2; i++) begin
        acc = to_s(lane_u(x, 16, 2*i), 16) * to_s(lane_u(z, 16, 2*i), 16) + to_s(lane_u(x, 16, 2*i + 1), 16) * to_s(lane_u(z, 16, 2*i + 1), 16);
        for (int k = 0; k < 32; k++) out[32*i + k] = acc[k];
      end
      return out;
    end
    if (opc == 18) begin                                                               // PSAD
      acc = 0;
      for (int l = 0; l < 8; l++) begin ux = lane_u(x, 8, l);  uz = lane_u(z, 8, l);  acc = acc + ((ux > uz) ? ux - uz : uz - ux); end
      for (int k = 0; k < 16; k++) out[k] = acc[k];
      return out;
    end
    for (int l = 0; l < nl; l++) begin
      ux = lane_u(x, lw, l);  uz = lane_u(z, lw, l);  sx = to_s(ux, lw);  sz = to_s(uz, lw);  res = 0;
      case (opc)
        0:  res = ux + uz;
        1:  res = ux - uz;
        2:  begin res = sx + sz; if (res > hi) res = hi; else if (res < lo) res = lo; end
        3:  begin res = sx - sz; if (res > hi) res = hi; else if (res < lo) res = lo; end
        4:  begin res = ux + uz; if (res > full) res = full; end
        5:  begin res = ux - uz; if (res < 0) res = 0; end
        6:  res = (ux < uz) ? ux : uz;
        7:  res = (ux > uz) ? ux : uz;
        8:  res = (sx < sz) ? sx : sz;
        9:  res = (sx > sz) ? sx : sz;
        10: res = (ux + uz + 1) / 2;
        11: res = (ux == uz) ? -1 : 0;
        12: res = (sx > sz) ? -1 : 0;
        13: res = ux * uz;
        15: res = (sh >= lw) ? 0 : ux * (64'sd1 <<< sh);
        16: res = (sh >= lw) ? 0 : ux / (64'sd1 <<< sh);
        17: begin
              if (sh >= lw) res = (sx < 0) ? -1 : 0;
              else begin res = sx / (64'sd1 <<< sh); if (sx < 0 && (sx % (64'sd1 <<< sh)) != 0) res = res - 1; end   // floor division = arithmetic shift
            end
        default: res = 0;
      endcase
      for (int k = 0; k < lw; k++) out[l * lw + k] = res[k];                            // two's-complement low bits
    end
    return out;
  endfunction

  // ---- DUT access ----------------------------------------------------------------------------------
  task automatic run(input int opc, input int es, input logic [63:0] x, input logic [63:0] z, input int sh, output logic [63:0] r);
    op = opc[4:0];  esize = es[1:0];  a = x;  b = z;  imm = sh[5:0];
    #1;
    simd_ops++;
    r = y;
  endtask
  task automatic chk(input string what, input int opc, input int es, input logic [63:0] x, input logic [63:0] z, input logic [63:0] exp_v, input logic [63:0] mask);
    logic [63:0] r;
    run(opc, es, x, z, 0, r);
    if ((r & mask) !== exp_v) begin errors++; $display("FAIL %s: got %h expected %h", what, r & mask, exp_v); end
  endtask
  function automatic logic [63:0] splat8(input logic [7:0] v); splat8 = {8{v}}; endfunction

  string opname [0:18];
  initial begin
    opname[0]="PADD"; opname[1]="PSUB"; opname[2]="PADDS"; opname[3]="PSUBS"; opname[4]="PADDUS"; opname[5]="PSUBUS"; opname[6]="PMINU";
    opname[7]="PMAXU"; opname[8]="PMINS"; opname[9]="PMAXS"; opname[10]="PAVGU"; opname[11]="PCMPEQ"; opname[12]="PCMPGTS"; opname[13]="PMULLO";
    opname[14]="PMADD"; opname[15]="PSLL"; opname[16]="PSRL"; opname[17]="PSRA"; opname[18]="PSAD";
  end

  task automatic expect64(input string what, input logic [63:0] got, input logic [63:0] exp_v);
    if (got !== exp_v) begin errors++; $display("FAIL %s: got %h expected %h", what, got, exp_v); end
  endtask

  initial begin
    logic [63:0] g, x, z;  int sh, n_checked;  int es_lo, es_hi;
    n_checked = 0;

    // ---- 1. directed -----------------------------------------------------------------------------
    // carries must stay inside their lane
    chk("PADD 8-bit  FF+01 per even byte -> 00 (no carry into the next byte)", 0, 0, 64'h00FF00FF00FF00FF, 64'h0001000100010001, 64'h0000000000000000, '1);
    chk("PADD 16-bit 00FF+0001 -> 0100 inside the lane",                       0, 1, 64'h00FF00FF00FF00FF, 64'h0001000100010001, 64'h0100010001000100, '1);
    chk("PADD 32-bit FFFFFFFF+1 -> 0, upper lane untouched",                   0, 2, 64'h00000001FFFFFFFF, 64'h0000000000000001, 64'h0000000100000000, '1);
    chk("PSUB 8-bit  [00-01, 01-00] -> [FF, 01]: the borrow stays in its byte",   1, 0, 64'h0100010001000100, 64'h0001000100010001, 64'h01FF01FF01FF01FF, '1);
    // saturation
    chk("PADDUS 8-bit F0+20 -> FF",                          4, 0, splat8(8'hF0), splat8(8'h20), splat8(8'hFF), '1);
    chk("PADD   8-bit F0+20 -> 10 (wraps: the artifact saturation avoids)", 0, 0, splat8(8'hF0), splat8(8'h20), splat8(8'h10), '1);
    chk("PADDS  8-bit 70+20 -> 7F",                          2, 0, splat8(8'h70), splat8(8'h20), splat8(8'h7F), '1);
    chk("PADDS  8-bit 80+80 -> 80",                          2, 0, splat8(8'h80), splat8(8'h80), splat8(8'h80), '1);
    chk("PSUBUS 8-bit 10-20 -> 00",                          5, 0, splat8(8'h10), splat8(8'h20), 64'd0, '1);
    chk("PSUBS  8-bit 80-01 -> 80",                          3, 0, splat8(8'h80), splat8(8'h01), splat8(8'h80), '1);
    chk("PAVGU  8-bit (255+254+1)/2 -> FF",                  10, 0, splat8(8'hFF), splat8(8'hFE), splat8(8'hFF), '1);
    chk("PSAD   |1-0| + |0-3| + 6 x |5-5| = 4",              18, 0, 64'h0505050505050001, 64'h0505050505050300, 64'd4, 64'hFFFF);
    chk("PMADD  (1*3 + 2*4) = 11,  (-5*2 + 7*3) = 11",        14, 1, 64'h0007FFFB00020001, 64'h0003000200040003, 64'h0000000B0000000B, '1);

    // ---- 2. every op x lane width ------------------------------------------------------------------
    for (int opc = 0; opc <= 18; opc++) begin
      es_lo = 0;  es_hi = 2;
      if (opc == 14) begin es_lo = 1; es_hi = 1; end
      if (opc == 18) begin es_lo = 0; es_hi = 0; end
      for (int es = es_lo; es <= es_hi; es++)
        for (int t = 0; t < 300; t++) begin
          x = rnd64();  z = rnd64();  sh = int'(rnd6()) % ((8 << es) + 2);        // shift counts include >= width
          case (t % 10)                                                                // edge-heavy operands
            0: begin x = 64'd0; end
            1: begin z = '1; end
            2: begin x = {8{8'h80}}; z = {8{8'h80}}; end
            3: begin x = {8{8'h7F}}; z = {8{8'h01}}; end
            default: ;
          endcase
          run(opc, es, x, z, sh, g);
          if (g !== ref_op(opc, es, x, z, sh)) begin
            errors++;  if (errors < 20) $display("FAIL %s esize=%0d a=%h b=%h imm=%0d: got %h expected %h", opname[opc], es, x, z, sh, g, ref_op(opc, es, x, z, sh));
          end
          n_checked++;
        end
    end
    $display("%0d op/width/operand combinations checked against the golden model", n_checked);

    // ---- 3. kernels ---------------------------------------------------------------------------------
    begin : kernels
      logic [7:0] img [0:63];  logic [63:0] word;  int scalar_ops, mism, wrapped, total, ssum;  logic [63:0] acc;
      logic signed [15:0] va [0:31], vb [0:31];  longint dot;  logic [31:0] lsum;
      logic signed [15:0] sx [0:31], sy [0:31];

      // brightness: saturating add of +90 to 64 pixels
      for (int i = 0; i < 64; i++) img[i] = rnd8();
      mism = 0; wrapped = 0; simd_ops = 0; scalar_ops = 64;
      for (int c = 0; c < 8; c++) begin
        logic [63:0] px, sat, wrap;
        for (int k = 0; k < 8; k++) px[8*k +: 8] = img[8*c + k];
        run(4, 0, px, splat8(8'd90), 0, sat);                                   // PADDUS
        run(0, 0, px, splat8(8'd90), 0, wrap);                                   // PADD  (what a plain wide add would do)
        for (int k = 0; k < 8; k++) begin
          int s;  s = int'(img[8*c + k]) + 90;  if (s > 255) s = 255;
          if (sat[8*k +: 8] !== s[7:0]) mism++;
          if (wrap[8*k +: 8] !== sat[8*k +: 8]) wrapped++;
        end
      end
      if (mism != 0) begin errors++; $display("FAIL brightness: %0d mismatches", mism); end
      total = 0;  for (int i = 0; i < 64; i++) if (int'(img[i]) + 90 > 255) total++;
      if (wrapped != total || total == 0) begin errors++; $display("FAIL brightness: %0d pixels differ between saturating and wrapping add, expected %0d (> 0)", wrapped, total); end
      $display("brightness : 64 pixels, %0d saturating SIMD adds (+%0d wrapping adds for comparison) vs %0d scalar ops; %0d pixels would wrap without saturation", simd_ops / 2, simd_ops / 2, scalar_ops, total);

      // SAD of an 8x8 block (motion estimation)
      ssum = 0;  acc = 0;  simd_ops = 0;
      for (int r = 0; r < 8; r++) begin
        logic [63:0] cur, ref_row, s;
        cur = rnd64();  ref_row = rnd64();
        run(18, 0, cur, ref_row, 0, s);  acc = acc + s[15:0];
        for (int k = 0; k < 8; k++) ssum = ssum + ((cur[8*k +: 8] > ref_row[8*k +: 8]) ? cur[8*k +: 8] - ref_row[8*k +: 8] : ref_row[8*k +: 8] - cur[8*k +: 8]);
      end
      if (int'(acc) != ssum) begin errors++; $display("FAIL SAD: %0d vs scalar %0d", acc, ssum); end
      $display("SAD 8x8    : %0d PSAD instructions (+ adds) vs 64 scalar absolute-difference steps, SAD = %0d", simd_ops, ssum);

      // 16-bit dot product with PMADD, 32 elements
      for (int i = 0; i < 32; i++) begin va[i] = rnd16(); vb[i] = rnd16(); end
      dot = 0;  for (int i = 0; i < 32; i++) dot = dot + longint'(va[i]) * longint'(vb[i]);
      simd_ops = 0;  acc = 0;
      for (int c = 0; c < 8; c++) begin
        logic [63:0] pa, pb, pm;
        for (int k = 0; k < 4; k++) begin pa[16*k +: 16] = va[4*c + k]; pb[16*k +: 16] = vb[4*c + k]; end
        run(14, 1, pa, pb, 0, pm);                                               // PMADD -> two 32-bit partial sums
        run(0, 2, acc, pm, 0, acc);                                               // PADD (32-bit lanes) accumulates
      end
      lsum = acc[31:0] + acc[63:32];                                                // horizontal add of the two lanes
      if (lsum !== dot[31:0]) begin errors++; $display("FAIL dot product: %h vs scalar %h", lsum, dot[31:0]); end
      $display("dot product: 32 MACs in %0d SIMD instructions (8 PMADD + 8 PADD) vs 64 scalar multiply/add ops", simd_ops);

      // saturating 16-bit audio mix of two 32-sample buffers
      for (int i = 0; i < 32; i++) begin sx[i] = rnd16(); sy[i] = rnd16(); end
      mism = 0;  simd_ops = 0;
      for (int c = 0; c < 8; c++) begin
        logic [63:0] pa, pb, pm;
        for (int k = 0; k < 4; k++) begin pa[16*k +: 16] = sx[4*c + k]; pb[16*k +: 16] = sy[4*c + k]; end
        run(2, 1, pa, pb, 0, pm);                                                 // PADDS
        for (int k = 0; k < 4; k++) begin
          int s;  s = int'(sx[4*c + k]) + int'(sy[4*c + k]);  if (s > 32767) s = 32767; if (s < -32768) s = -32768;
          if ($signed(pm[16*k +: 16]) !== s) mism++;
        end
      end
      if (mism != 0) begin errors++; $display("FAIL audio mix: %0d mismatches", mism); end
      $display("audio mix  : 32 samples in %0d saturating SIMD adds vs 32 scalar adds + clamps", simd_ops);
    end

    if (errors == 0) $display("TEST PASSED"); else $display("TEST FAILED: %0d errors", errors);
    $finish;
  end
endmodule
