// 16-bit two-level carry-lookahead adder (Appendix J).
// Level 1: each 4-bit block computes its own carries by lookahead and exports group G/P.
// Level 2: a lookahead unit computes the block carry-ins from the group G/P in parallel
//          (no carry ripples between blocks).
module cla4_block (
    input  logic [3:0] a, b,
    input  logic       cin,
    output logic [3:0] sum,
    output logic       g_grp, p_grp
);
  logic [3:0] g, p;
  logic       c1, c2, c3;
  always_comb begin
    g = a & b;  p = a ^ b;
    c1 = g[0] | (p[0] & cin);
    c2 = g[1] | (p[1] & g[0]) | (p[1] & p[0] & cin);
    c3 = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & cin);
    sum   = p ^ {c3, c2, c1, cin};
    g_grp = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]);
    p_grp = &p;
  end
endmodule

module carry_lookahead_adder (
    input  logic [15:0] a, b,
    input  logic        cin,
    output logic [15:0] sum,
    output logic        cout
);
  logic [3:0] G, P;
  logic [3:0] c;                       // carry into each block
  always_comb begin
    c[0] = cin;
    c[1] = G[0] | (P[0] & cin);
    c[2] = G[1] | (P[1] & G[0]) | (P[1] & P[0] & cin);
    c[3] = G[2] | (P[2] & G[1]) | (P[2] & P[1] & G[0]) | (P[2] & P[1] & P[0] & cin);
    cout = G[3] | (P[3] & G[2]) | (P[3] & P[2] & G[1]) | (P[3] & P[2] & P[1] & G[0]) | (&P & cin);
  end
  genvar i;
  generate
    for (i = 0; i < 4; i++) begin : blk
      cla4_block u (.a(a[4*i +: 4]), .b(b[4*i +: 4]), .cin(c[i]), .sum(sum[4*i +: 4]), .g_grp(G[i]), .p_grp(P[i]));
    end
  endgenerate
endmodule
