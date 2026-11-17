// 4x4 output-stationary matrix multiply. Four skewed A rows enter from
// the left and four skewed B columns enter from the top over ten wavefronts.
module systolic_os_act_quant (
    input logic clk, reset, start,
    input logic [127:0] matrix_a, matrix_b,
    input logic [511:0] bias,
    input logic [1:0] activation, input logic [4:0] shift,
    output logic busy, done,
    output logic [511:0] accumulators,
    output logic [127:0] quantized
);
    logic [127:0] a_latched, b_latched;
    logic [511:0] bias_latched;
    logic [1:0] activation_latched;
    logic [4:0] shift_latched;
    logic [3:0] step;
    logic signed [7:0] a_pipe [0:15], b_pipe [0:15];
    logic signed [31:0] acc [0:15];
    logic signed [7:0] a_in [0:15], b_in [0:15];
    logic signed [32:0] value;
    integer r,c,k,ix;
    function automatic signed [31:0] product(input logic signed [7:0] left, right);
        logic signed [31:0] aa, bb;
        begin aa=left; bb=right; product=aa*bb; end
    endfunction
    always_comb begin
        for (integer row=0;row<4;row=row+1)
            for (integer col=0;col<4;col=col+1) begin
                if (col==0) begin
                    if (step>=row && step<row+4) a_in[row*4+col]=a_latched[(row*4+(step-row))*8 +: 8];
                    else a_in[row*4+col]=0;
                end else a_in[row*4+col]=a_pipe[row*4+col-1];
                if (row==0) begin
                    if (step>=col && step<col+4) b_in[row*4+col]=b_latched[((step-col)*4+col)*8 +: 8];
                    else b_in[row*4+col]=0;
                end else b_in[row*4+col]=b_pipe[(row-1)*4+col];
            end
        accumulators='0; quantized='0; value=0;
        for (integer pos=0;pos<16;pos=pos+1) begin
            accumulators[pos*32 +: 32]=acc[pos];
            value=$signed({acc[pos][31],acc[pos]}) + $signed({bias_latched[pos*32+31],bias_latched[pos*32 +: 32]});
            if (activation_latched!=0 && value<0) value=0;
            if (activation_latched==2 && value>6) value=6;
            value=value >>> shift_latched;
            if (value>127) quantized[pos*8 +: 8]=8'h7f;
            else if (value< -128) quantized[pos*8 +: 8]=8'h80;
            else quantized[pos*8 +: 8]=value[7:0];
        end
    end
    always_ff @(posedge clk) begin
        if (reset) begin
            busy<=0; done<=0; step<=0; a_latched<=0; b_latched<=0; bias_latched<=0;
            activation_latched<=0; shift_latched<=0;
            for (ix=0;ix<16;ix=ix+1) begin a_pipe[ix]<=0; b_pipe[ix]<=0; acc[ix]<=0; end
        end else begin
            done<=0;
            if (start && !busy) begin
                busy<=1; step<=0; a_latched<=matrix_a; b_latched<=matrix_b; bias_latched<=bias;
                activation_latched<=activation; shift_latched<=shift;
                for (ix=0;ix<16;ix=ix+1) begin a_pipe[ix]<=0; b_pipe[ix]<=0; acc[ix]<=0; end
            end else if (busy) begin
                for (r=0;r<4;r=r+1) for (c=0;c<4;c=c+1) begin
                    a_pipe[r*4+c]<=a_in[r*4+c]; b_pipe[r*4+c]<=b_in[r*4+c];
                    acc[r*4+c]<=acc[r*4+c]+product(a_in[r*4+c],b_in[r*4+c]);
                end
                if (step==9) begin busy<=0; done<=1; end else step<=step+1'b1;
            end
        end
    end
endmodule
