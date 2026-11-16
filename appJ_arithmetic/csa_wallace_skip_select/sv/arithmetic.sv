// 16-bit, four-bit-group carry-skip and carry-select adders, and an 8x8
// carry-save reduction multiplier. Unsigned arithmetic throughout.
module carry_skip16(input logic [15:0] a, b, input logic cin,
                    output logic [15:0] sum, output logic cout);
    logic [4:0] group_carry;
    logic [4:0] local_sum;
    integer g;
    always_comb begin
        group_carry = '0;
        sum = '0;
        local_sum = '0;
        group_carry[0] = cin;
        for (g = 0; g < 4; g = g + 1) begin
            local_sum = {1'b0, a[g*4 +: 4]} + {1'b0, b[g*4 +: 4]} + group_carry[g];
            sum[g*4 +: 4] = local_sum[3:0];
            group_carry[g+1] = (&(a[g*4 +: 4] ^ b[g*4 +: 4])) ? group_carry[g] : local_sum[4];
        end
        cout = group_carry[4];
    end
endmodule

module carry_select16(input logic [15:0] a, b, input logic cin,
                      output logic [15:0] sum, output logic cout);
    logic [4:0] group_carry;
    logic [4:0] zero_result, one_result, chosen;
    integer g;
    always_comb begin
        group_carry = '0;
        sum = '0;
        zero_result = '0;
        one_result = '0;
        chosen = '0;
        group_carry[0] = cin;
        for (g = 0; g < 4; g = g + 1) begin
            zero_result = {1'b0, a[g*4 +: 4]} + {1'b0, b[g*4 +: 4]};
            one_result = {1'b0, a[g*4 +: 4]} + {1'b0, b[g*4 +: 4]} + 5'd1;
            chosen = group_carry[g] ? one_result : zero_result;
            sum[g*4 +: 4] = chosen[3:0];
            group_carry[g+1] = chosen[4];
        end
        cout = group_carry[4];
    end
endmodule

module wallace8(input logic [7:0] a, b, output logic [15:0] product);
    logic [15:0] p [0:7];
    logic [15:0] s0, c0, s1, c1, s2, c2, s3, c3, s4, c4, s5, c5;
    integer i;
    always_comb begin
        for (i = 0; i < 8; i = i + 1)
            p[i] = b[i] ? ({8'b0, a} << i) : 16'b0;
        s0 = p[0] ^ p[1] ^ p[2];
        c0 = ((p[0] & p[1]) | (p[0] & p[2]) | (p[1] & p[2])) << 1;
        s1 = p[3] ^ p[4] ^ p[5];
        c1 = ((p[3] & p[4]) | (p[3] & p[5]) | (p[4] & p[5])) << 1;
        s2 = s0 ^ c0 ^ s1;
        c2 = ((s0 & c0) | (s0 & s1) | (c0 & s1)) << 1;
        s3 = c1 ^ p[6] ^ p[7];
        c3 = ((c1 & p[6]) | (c1 & p[7]) | (p[6] & p[7])) << 1;
        s4 = s2 ^ c2 ^ s3;
        c4 = ((s2 & c2) | (s2 & s3) | (c2 & s3)) << 1;
        s5 = s4 ^ c4 ^ c3;
        c5 = ((s4 & c4) | (s4 & c3) | (c4 & c3)) << 1;
        product = s5 + c5;
    end
endmodule
