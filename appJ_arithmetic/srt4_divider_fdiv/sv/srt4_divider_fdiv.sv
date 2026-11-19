module srt4_divider_fdiv #(
    parameter bit PENTIUM_FDIV_BUG=0
)(
    input logic clk, reset, start,
    input logic [31:0] numerator, denominator,
    output logic busy, done, divide_by_zero, fault_hit,
    output logic [31:0] quotient, remainder,
    output logic signed [65:0] mantissa,
    output logic signed [6:0] exponent
);
    localparam ROM_FILE="../../../../appJ_arithmetic/srt4_divider_fdiv/selection.txt";
    logic [2:0] selection [0:2047];
    initial $readmemb(ROM_FILE,selection);
    logic [34:0] sum_word, carry_word, divisor;
    logic [31:0] saved_n, saved_d;
    logic signed [66:0] prefix, prefix_minus_one;
    integer iteration;
    function automatic integer top_bit(input logic [31:0] word);
        top_bit=0;
        for (integer i=0;i<32;i=i+1) if (word[i]) top_bit=i;
    endfunction

    always @(posedge clk) begin : step
        integer hi_n, hi_d, column, digit, right_shift;
        logic signed [6:0] row;
        logic [34:0] term, new_sum, new_carry, twice_divisor, multiple;
        logic subtract, omitted;
        logic signed [66:0] next_prefix, next_minus, integer_part;
        logic [1:0] suffix;
        logic [63:0] product;
        logic signed [64:0] residual;
        if (reset) begin
            busy<=0; done<=0; divide_by_zero<=0; fault_hit<=0;
            quotient<=0; remainder<=0; mantissa<=0; exponent<=0;
            sum_word<=0; carry_word<=0; divisor<=0;
            saved_n<=0; saved_d<=0; prefix<=0; prefix_minus_one<=-1; iteration<=0;
        end else begin
            done<=0;
            if (!busy && start) begin
                fault_hit<=0; divide_by_zero<=denominator==0;
                if (denominator==0) begin
                    quotient<=32'hffffffff; remainder<=numerator; mantissa<=0; exponent<=0; done<=1;
                end else if (numerator==0) begin
                    quotient<=0; remainder<=0; mantissa<=0; exponent<=0; done<=1;
                end else begin
                    hi_n=top_bit(numerator); hi_d=top_bit(denominator);
                    exponent<=hi_n-hi_d;
                    sum_word<={3'b0,numerator}<<(31-hi_n);
                    divisor<={3'b0,denominator}<<(31-hi_d);
                    carry_word<=0; prefix<=0; prefix_minus_one<=-1; iteration<=0;
                    saved_n<=numerator; saved_d<=denominator; busy<=1;
                end
            end else if (busy) begin
                row=sum_word[34:28]+carry_word[34:28];
                column=int'(divisor[31:27]);
                digit=int'(selection[128*(column-16)+64+int'(row)])-2;
                omitted=PENTIUM_FDIV_BUG && ((column+1)%3==0) && int'(row)==4*(column+1)/3-1;
                if (omitted) begin digit=0; fault_hit<=1; end
                subtract=digit>0;
                twice_divisor=divisor<<1;
                case (digit)
                    -2,2: multiple=twice_divisor;
                    -1,1: multiple=divisor;
                    default: multiple=0;
                endcase
                term=subtract ? ~multiple : multiple;
                new_sum=sum_word^carry_word^term;
                new_carry=((sum_word&carry_word)|(sum_word&term)|(carry_word&term))<<1;
                new_carry[0]=subtract;
                sum_word<=new_sum<<2; carry_word<=new_carry<<2;
                suffix=digit;
                next_prefix=(digit>=0 ? prefix : prefix_minus_one)<<2;
                next_prefix[1:0]=suffix;
                suffix=digit-1;
                next_minus=(digit>0 ? prefix : prefix_minus_one)<<2;
                next_minus[1:0]=suffix;
                prefix<=next_prefix; prefix_minus_one<=next_minus;
                if (iteration==32) begin
                    mantissa<=next_prefix[65:0];
                    right_shift=64-int'(exponent);
                    integer_part=next_prefix>>>right_shift;
                    product=integer_part[31:0]*saved_d;
                    residual=$signed({33'b0,saved_n})-$signed({1'b0,product});
                    if (!fault_hit && !omitted) begin
                        if (residual<0) begin integer_part=integer_part-1; residual=residual+$signed({33'b0,saved_d}); end
                        else if (residual>=$signed({33'b0,saved_d})) begin
                            integer_part=integer_part+1; residual=residual-$signed({33'b0,saved_d});
                        end
                    end
                    quotient<=integer_part[31:0]; remainder<=residual[31:0]; busy<=0; done<=1;
                end else iteration<=iteration+1;
            end
        end
    end
endmodule
