// Streaming 3x3 signed-int8 cross-correlation, one input per enabled cycle.
// Kernel lane 0 is top-left; output is valid only for complete windows.
module conv2d_linebuffer #(parameter WIDTH=16, HEIGHT=16) (
    input logic clk, reset, input logic in_valid,
    input logic signed [7:0] pixel, input logic [71:0] kernel,
    output logic out_valid, output logic signed [31:0] result
);
    logic [7:0] previous [0:WIDTH-1], older [0:WIDTH-1];
    logic [7:0] top_l2, top_l1, mid_l2, mid_l1, bot_l2, bot_l1;
    integer x, y, i;
    function automatic signed [31:0] mul8(input logic [7:0] left, right);
        logic signed [31:0] a,b;
        begin a=$signed(left); b=$signed(right); mul8=a*b; end
    endfunction
    always_ff @(posedge clk) begin
        if (reset) begin
            x<=0; y<=0; out_valid<=0; result<=0;
            top_l2<=0; top_l1<=0; mid_l2<=0; mid_l1<=0; bot_l2<=0; bot_l1<=0;
            for (i=0;i<WIDTH;i=i+1) begin previous[i]<=0; older[i]<=0; end
        end else begin
            out_valid<=0;
            if (in_valid) begin
                if (x>=2 && y>=2) begin
                    result <= mul8(top_l2,kernel[7:0]) + mul8(top_l1,kernel[15:8]) + mul8(older[x],kernel[23:16]) +
                              mul8(mid_l2,kernel[31:24]) + mul8(mid_l1,kernel[39:32]) + mul8(previous[x],kernel[47:40]) +
                              mul8(bot_l2,kernel[55:48]) + mul8(bot_l1,kernel[63:56]) + mul8(pixel,kernel[71:64]);
                    out_valid<=1;
                end
                older[x]<=previous[x]; previous[x]<=pixel;
                top_l2<=top_l1; top_l1<=older[x];
                mid_l2<=mid_l1; mid_l1<=previous[x];
                bot_l2<=bot_l1; bot_l1<=pixel;
                if (x==WIDTH-1) begin x<=0; if (y==HEIGHT-1) y<=0; else y<=y+1; end
                else x<=x+1;
            end
        end
    end
endmodule
