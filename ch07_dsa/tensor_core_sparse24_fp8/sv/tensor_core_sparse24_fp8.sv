module tensor_core_sparse24_fp8(
    input logic clk, reset, start, sparse,
    input logic [1:0] format,
    input logic signed [7:0] scale_a, scale_b,
    input logic [255:0] a_tile,
    input logic [511:0] c_tile,
    input logic [15:0] indices, // two ascending 2-bit k indices per column
    output wire weight_read,
    output wire [1:0] weight_slot,
    input logic [63:0] weights, // four column banks, combinational read
    output logic busy, done, error,
    output logic [2:0] compute_cycles,
    output logic [4:0] weight_reads, flags,
    output logic [511:0] d_tile
);
    logic sparse_q;
    logic [1:0] slot, format_q;
    logic signed [7:0] sa, sb;
    logic [255:0] a_q;
    logic [15:0] map_q;
    wire [511:0] next_d;
    wire [79:0] lane_flags;
    assign weight_read=busy;
    assign weight_slot=slot;

    for (genvar col=0; col<4; col=col+1) begin : column
        wire [1:0] k = sparse_q ? map_q[4*col+2*slot +: 2] : slot;
        for (genvar row=0; row<4; row=row+1) begin : lane
            localparam integer L=4*row+col;
            wire [15:0] a_operand=a_q[16*(4*row+k) +: 16];
            ieee754_fpu_fma_bf16 fma(
                2'd2,format_q,2'd0,{16'b0,a_operand},{16'b0,weights[16*col +: 16]},
                d_tile[32*L +: 32],sa,sb,next_d[32*L +: 32],lane_flags[5*L +: 5]
            );
        end
    end

    always @(posedge clk) begin : step
        logic invalid;
        logic [4:0] new_flags;
        if (reset) begin
            busy<=0; done<=0; error<=0; compute_cycles<=0; weight_reads<=0; flags<=0;
            d_tile<=0; sparse_q<=0; slot<=0; format_q<=0; sa<=0; sb<=0; a_q<=0; map_q<=0;
        end else begin
            done<=0;
            if (busy) begin
                new_flags=flags;
                for (integer i=0; i<16; i=i+1) new_flags=new_flags|lane_flags[5*i +: 5];
                flags<=new_flags;
                d_tile<=next_d;
                compute_cycles<=compute_cycles+1;
                weight_reads<=weight_reads+4;
                if (slot==(sparse_q ? 2'd1 : 2'd3)) begin busy<=0; done<=1; end
                else slot<=slot+1;
            end else if (start) begin
                invalid=(format==0);
                if (sparse)
                    for (integer col=0; col<4; col=col+1)
                        if (indices[4*col +: 2]>=indices[4*col+2 +: 2]) invalid=1;
                error<=invalid; d_tile<=c_tile;
                compute_cycles<=0; weight_reads<=0; flags<=0; slot<=0;
                if (invalid) done<=1;
                else begin
                    busy<=1; sparse_q<=sparse; format_q<=format; a_q<=a_tile;
                    map_q<=indices; sa<=scale_a; sb<=scale_b;
                end
            end
        end
    end
endmodule
